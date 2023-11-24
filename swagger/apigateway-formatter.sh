#!/bin/bash
# Check if the env argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <env>"
    exit 1
fi

ENV="$1"
# Read the OpenAPI file into a variable
openapi_file="openapi.json"
base_uri="https://\${stageVariables.SERVICE_NAME}.$ENV.llzgarantidora.com"

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
    "uri": "$base_uri$path",
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
paths=$(jq -c '.paths | to_entries[]' "$openapi_file")

# Initialize openapi_data
openapi_data=$(cat "$openapi_file")

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
  echo "$openapi_data" > "$openapi_file"
  echo "Script executed successfully."
else
  echo "Error: openapi_data is empty. Script did not execute successfully."
fi

aws apigateway put-rest-api --rest-api-id "enq3zuko73" --mode overwrite --body "fileb://openapi.json"
aws apigateway create-deployment --rest-api-id "enq3zuko73" --stage-name "$ENV"