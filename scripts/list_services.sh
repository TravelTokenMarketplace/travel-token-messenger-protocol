#!/bin/bash

# The following cut down the list of all the services defined by protobuf looking like this:
# ttm/services/activity/v2/search.proto:service ActivitySearchService
# ttm/services/activity/v2/list.proto:service ActivityProductListService
# ttm/services/activity/v2/info.proto:service ActivityProductInfoService
# ttm/services/network/v1/fee.proto:service GetNetworkFeeService

cd proto
while read service ; do
	FN=$(echo $service | cut -d":" -f1)
	SERVICE_NAME=$(echo $service | cut -d" " -f2)
	SERVICE_PATH=$(dirname $FN | tr "/" ".")

	echo "$SERVICE_PATH.$SERVICE_NAME"

done < <(grep -oP "^service \w+" -r *)
