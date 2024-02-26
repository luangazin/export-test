#!/bin/bash
HOST_NAME="rest.apr.vee.codes"

#Exporting from Openapi to Kong Ingress
inso generate config openapi-swagger.yaml --type kubernetes --output kong.yaml
PROJECT_NAME=$(yq e '(select(di == 0) | select(.kind == "Ingress") | .metadata.name)' kong.yaml | sed 's/-0//g')

#Count the number of ingresses
INGRESS_COUNT=$(yq e 'select(.kind == "Ingress") | length' kong.yaml | wc -l)

#Iterate through the ingresses and create a service.yaml file
for ((i=0; i<$INGRESS_COUNT; i++)); do
    NEW_PROJECT_NAME=${PROJECT_NAME}
    if [ $i -gt 0 ]; then
        NEW_PROJECT_NAME=${PROJECT_NAME}${i}
        echo "---" >> service.yaml
    fi
    PROJECT_PATH=$(yq e "(select(di == $i) | select(.kind == \"Ingress\") | .spec.rules[0].http.paths[0].path // \"\")" kong.yaml) || result=""
    yq e "(select(di == $i) | select(.kind == \"Ingress\") | .spec.rules[0].http.paths[0].path) |= \"/${NEW_PROJECT_NAME}${PROJECT_PATH}\"" -i kong.yaml
    SERVICE_NAME=$(yq e "(select(di == $i) | select(.kind == \"Ingress\") | .spec.rules[0].http.paths[0].backend.service.name)" kong.yaml)
    HOST_EXTERNAL=$(yq e "(select(di == $i) | select(.kind == \"Ingress\") | .spec.rules[0].host)" kong.yaml)
    kubectl create service externalname $SERVICE_NAME --external-name ${HOST_EXTERNAL} --dry-run=client -o=yaml | \
    yq -e 'del(.spec.selector) | del(.metadata.creationTimestamp) | del(.status) | del(.metadata.labels)' >> service.yaml
done

#Modify the kong.yaml file adapting to Kong Ingress
yq e '(select(.kind == "Ingress") | .spec.ingressClassName) |= "kong"' -i kong.yaml
yq e "(select(.kind == \"Ingress\") | .spec.rules[0].http.paths[0].pathType) |= \"Prefix\"" -i kong.yaml
yq e "(select(.kind == \"Ingress\") | .spec.rules[0].host) |= \"${HOST_NAME}\"" -i kong.yaml

#Merging files
yq service.yaml kong.yaml > kong-kubernetes.yaml

#Cleaning up
rm service.yaml kong.yaml