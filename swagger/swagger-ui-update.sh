#!/bin/bash

# Check if the service argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <service>"
    exit 1
fi

# Set the service name from the argument
SERVICE="$1"
BUCKET_NAME="dev-api-swagger"
LOCAL_FILE="swagger/openapi.json"
DOCS_DIR="$BUCKET_NAME/docs"
DOCS_LIST_FILE="$BUCKET_NAME/docs-list.json"

# Upload docs file to S3 bucket
aws s3 cp "$LOCAL_FILE" "s3://$DOCS_DIR/$SERVICE.json" --profile hlisboa

# Check if the upload was successful
if [ $? -ne 0 ]; then
    echo "Error: Swagger UI update - uploading docs bucket."
    exit 1
fi

# Append the new object to the docs-list.json file
NEW_OBJECT="{ \"url\": \"docs/$SERVICE.json\" , \"name\": \"$SERVICE\" }"
jq ". += [$NEW_OBJECT]" "$DOCS_LIST_FILE" > tmp_docs_list.json && mv tmp_docs_list.json "$DOCS_LIST_FILE"

# Upload the modified docs-list.json file back to the S3 bucket
aws s3 cp "$DOCS_LIST_FILE" "s3://$BUCKET_NAME/$DOCS_LIST_FILE" --profile hlisboa

# Check if the upload was successful
if [ $? -ne 0 ]; then
    echo "Error: Swagger UI update - updating docs-list file."
    exit 1
fi

echo "Swagger UI update completed for $SERVICE"