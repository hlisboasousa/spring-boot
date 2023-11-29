#!/bin/bash

# This script does the following:
#   - formats the OpenAPI file to be compatible with API Gateway. 
#   - updates the API Gateway definition.
#   - deploys the API Gateway to the stage environment provided as argument
#   - updates the Swagger UI docs in S3.

SWAGGER_BUCKET="$ENV-api-swagger"

API_ID=$(aws apigateway get-rest-apis --query 'items[?name==`LLZ-DEV`].[id]' --output text)
if [ $? -ne 0 ]; then
    echo "Error: Failed to get the API ID."
    exit 1
fi

# Function to process each path in the OpenAPI file and to add the aws-apigateway-integration block
insert_aws_integration() {
  local path_name="$1"
  local path_data="$2"

  # Loop through each method for the path
  for method in $(echo "$path_data" | jq -r 'keys[]'); do
    # Extract method, path, and parameters
    local path=$(echo "$path_name" | sed 's/^{.*}$/\\1/g')  # Extract path and remove curly braces if present
    local parameters=$(echo "$path_data" | jq -r ".$method.parameters[]?.name")

    # Generate output for x-amazon-apigateway-integration
    integration_block=$(cat <<-EOL
{
  "x-amazon-apigateway-integration": {
    "httpMethod": "$method",
    "uri": "$BASE_URI$path",
    "responses": {
      "default": {
        "statusCode": "200"
      }
    },
    "requestParameters": {
EOL
    )

    # Loop through parameters and add them to the output
    for param in $parameters; do
      integration_block+="      \"integration.request.path.$param\": \"method.request.path.$param\","
    done

    integration_block+="    },
    \"passthroughBehavior\": \"when_no_templates\",
    \"type\": \"http\"
  }
}"

    # Update the original OpenAPI data with the integration block
    openapi_data=$(jq ".paths.\"$path\".$method += $integration_block" <<< "$openapi_data")
  done
}

# Extract paths from the OpenAPI file
paths=$(jq -c '.paths | to_entries[]' "$OPENAPI_JSON_PATH")

# Initialize openapi_data
openapi_data=$(cat "$OPENAPI_JSON_PATH")

# Loop through each path and process it
while IFS= read -r path_entry; do
  path_name=$(echo "$path_entry" | jq -r '.key')
  path_data=$(echo "$path_entry" | jq -c -r '.value')
  insert_aws_integration "$path_name" "$path_data"
done <<< "$paths"

# Add/overwrite the securitySchemes object directly
security_schemes='{
  "auth-llz": {
    "type": "apiKey",
    "name": "Authorization",
    "in": "header",
    "x-amazon-apigateway-authtype": "cognito_user_pools"
  }
}'
if [ "$(echo "$openapi_data" | jq -c '.components')" != "null" ]; then
  openapi_data=$(echo "$openapi_data" | jq ".components.securitySchemes = $security_schemes")
else
  openapi_data=$(echo "$openapi_data" | jq ".components = {\"securitySchemes\": $security_schemes}")
fi

# Check if openapi_data is not empty before overwriting the file
if [ -n "$openapi_data" ]; then
  echo "$openapi_data" > "$OPENAPI_JSON_PATH"
  echo "openapi.json formatted succesfully."
else
  echo "Error: openapi.json is empty. Script did not execute successfully."
  exit 1
fi

# Download the current API definition from API Gateway
aws apigateway get-export --rest-api-id "$API_ID" --stage-name "$ENV" --export-type swagger --parameters extensions='apigateway' old-openapi.json
if [ $? -ne 0 ]; then
    echo "Error: Failed to get the API definition."
    exit 1
fi

# Merge the new API definition
# Overwriting the paths object directly based on the service name (e.g. /api/administradoras)
jq --argjson new "$openapi_data" --argjson old "$(cat old-openapi.json)" '
  ($new | .paths) as $newPaths |
  ($old | .paths) as $oldPaths |
  .paths = ($newPaths | reduce keys[] as $key (
    $oldPaths;
    if ($key | startswith("$BASE_PATH")) then
      .[$key] = $newPaths[$key]
    else
      .[$key] = ($newPaths[$key])
    end
  ))
' old-openapi.json > $OPENAPI_JSON_PATH

# Update API Gateway
aws apigateway put-rest-api --rest-api-id "$API_ID" --mode overwrite --body "fileb://$OPENAPI_JSON_PATH" > /dev/null
if [ $? -ne 0 ]; then
    echo "Error: Failed to update the API."
    exit 1
else
    echo "API updated successfully."
fi

# Clean up temporary files
rm old-openapi.json

# Deploy API Gateway
aws apigateway create-deployment --rest-api-id "$API_ID" --stage-name "$ENV" > /dev/null
if [ $? -ne 0 ]; then
    echo "Error: Failed to deploy the API."
    exit 1
else
    echo "API deployed successfully."
fi

# Update Swagger-UI on S3
aws s3 cp "$OPENAPI_JSON_PATH" "s3://$SWAGGER_BUCKET/docs/openapi.json"
if [ $? -ne 0 ]; then
    echo "Error: Swagger UI update - uploading OpenAPI file."
    exit 1
fi

echo "Swagger UI updated successfully."