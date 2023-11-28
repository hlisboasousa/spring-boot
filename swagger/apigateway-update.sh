#!/bin/bash

# This script does the following:
#   - formats the OpenAPI file to be compatible with API Gateway. 
#   - updates and deploys the API Gateway to the environment provided as argument.
#   - updates the Swagger UI docs in S3.

if [ -z "$1" ]; then
    echo "Usage: $0 <env>"
    exit 1
fi

ENV="$1"
SERVICE_NAME="administradora"
BASE_URI="https://${SERVICE_NAME}.$ENV.llzgarantidora.com"
OPENAPI_JSON_PATH="openapi.json"

BUCKET_NAME="dev-api-swagger"
DOCS_DIR="$BUCKET_NAME/docs"
DOCS_LIST_JSON="$BUCKET_NAME/docs-list.json"


# Function to process each path in the OpenAPI file
process_path() {
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
  process_path "$path_name" "$path_data"
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
# Check if "components" key exists in the original OpenAPI data
if [ "$(echo "$openapi_data" | jq -c '.components')" != "null" ]; then
  # Add/overwrite the securitySchemes object directly within the existing components object
  openapi_data=$(echo "$openapi_data" | jq ".components.securitySchemes = $security_schemes")
else
  # If "components" key does not exist, create it along with securitySchemes
  openapi_data=$(echo "$openapi_data" | jq ".components = {\"securitySchemes\": $security_schemes}")
fi

# Check if openapi_data is not empty before overwriting the file
if [ -n "$openapi_data" ]; then
  # Overwrite the original OpenAPI file
  echo "$openapi_data" > "$OPENAPI_JSON_PATH"
  echo "openapi.json formatted succesfully."
else
  echo "Error: openapi.json is empty. Script did not execute successfully."
  exit 1
fi

aws apigateway put-rest-api --rest-api-id "enq3zuko73" --mode overwrite --body "fileb://openapi.json" > /dev/null

if [ $? -ne 0 ]; then
    echo "Error: Failed to update the API."
    exit 1
else
    echo "API updated successfully."
fi

aws apigateway create-deployment --rest-api-id "enq3zuko73" --stage-name "$ENV" > /dev/null

if [ $? -ne 0 ]; then
    echo "Error: Failed to deploy the API."
    exit 1
else
    echo "API deployed successfully."
fi

# Update Swagger-UI on S3

aws s3 cp "$OPENAPI_JSON_PATH" "s3://$DOCS_DIR/$SERVICE_NAME.json"

# Download the current docs-list.json file from S3
aws s3 cp "s3://$DOCS_LIST_JSON" "current-docs-list.json"

# Check if the download was successful
if [ $? -ne 0 ]; then
    echo "Error: Swagger UI update - downloading current docs list."
    exit 1
fi

# Add the new entry to the docs list
new_entry="{\"url\": \"docs/$SERVICE_NAME.json\", \"name\": \"$SERVICE_NAME\"}"
jq ". += [$new_entry]" current-docs-list.json > updated-docs-list.json

# Upload the updated docs-list.json file back to S3
aws s3 cp "updated-docs-list.json" "s3://$DOCS_LIST_JSON"

# Check if the upload was successful
if [ $? -ne 0 ]; then
    echo "Error: Swagger UI update - error on uploading docs list."
    exit 1
fi

# Clean up temporary files
rm current-docs-list.json updated-docs-list.json
echo "Swagger UI updated successfully."