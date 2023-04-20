#!/bin/bash

source $TEST_DIR/common

MY_DIR=$(readlink -f `dirname "${BASH_SOURCE[0]}"`)

source ${MY_DIR}/../util
RESOURCEDIR="${MY_DIR}/../resources"

os::test::junit::declare_suite_start "$MY_SCRIPT"

function check_resources() {
    header "Testing Data Science Pipelines installation"
    os::cmd::expect_success "oc project ${ODHPROJECT}"
    os::cmd::try_until_text "oc get crd pipelineruns.tekton.dev " "pipelineruns.tekton.dev" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "oc get pods -l application-crd-id=data-science-pipelines --field-selector='status.phase!=Running,status.phase!=Completed' -o jsonpath='{$.items[*].metadata.name}' | wc -w" "0" $odhdefaulttimeout $odhdefaultinterval
    running_pods=$(oc get pods -l application-crd-id=data-science-pipelines --field-selector='status.phase=Running' -o jsonpath='{$.items[*].metadata.name}' | wc -w)
    os::cmd::expect_success "if [ "$running_pods" -gt "0" ]; then exit 0; else exit 1; fi"
}

function check_ui_overlay() {
    header "Checking UI overlay Kfdef deploys the UI"
    os::cmd::try_until_text "oc get pods -l app=ds-pipeline-ui --field-selector='status.phase=Running' -o jsonpath='{$.items[*].metadata.name}' | wc -w" "1" $odhdefaulttimeout $odhdefaultinterval
}

function create_pipeline() {
    header "Creating a pipeline"
    route=`oc get route ds-pipeline || echo ""`
    if [[ -z $route ]]; then
        oc expose service ds-pipeline
    fi
    sleep 60  #TODO: quick fix for race condition, implement a better check to begin test execution once service is ready
    ROUTE=$(oc get route ds-pipeline --template={{.spec.host}})
    PIPELINE_ID=$(curl -s -F "uploadfile=@${RESOURCEDIR}/ds-pipelines/test-pipeline-run.yaml" ${ROUTE}/apis/v1beta1/pipelines/upload | jq -r .id)
    os::cmd::try_until_not_text "curl -s ${ROUTE}/apis/v1beta1/pipelines/${PIPELINE_ID} | jq" "null" $odhdefaulttimeout $odhdefaultinterval
}

function list_pipelines() {
    header "Listing pipelines"
    os::cmd::try_until_text "curl -s ${ROUTE}/apis/v1beta1/pipelines | jq '.total_size'" "2" $odhdefaulttimeout $odhdefaultinterval
}

function create_run() {
    header "Creating a run"
    RUN_ID=$(curl -s -H "Content-Type: application/json" -X POST ${ROUTE}/apis/v1beta1/runs -d "{\"name\":\"test-pipeline-run_run\", \"pipeline_spec\":{\"pipeline_id\":\"${PIPELINE_ID}\"}}" | jq -r .run.id)
    os::cmd::try_until_not_text "curl -s ${ROUTE}/apis/v1beta1/runs/${RUN_ID} | jq '" "null" $odhdefaulttimeout $odhdefaultinterval
}

function list_runs() {
    header "Listing runs"
    os::cmd::try_until_text "curl -s ${ROUTE}/apis/v1beta1/runs | jq '.total_size'" "1" $odhdefaulttimeout $odhdefaultinterval
}

function check_run_status() {
    header "Checking run status"
    os::cmd::try_until_text "curl -s ${ROUTE}/apis/v1beta1/runs/${RUN_ID} | jq '.run.status'" "Completed" $odhdefaulttimeout $odhdefaultinterval
}

function setup_monitoring() {
    header "Enabling User Workload Monitoring on the cluster"
    oc apply -f ${RESOURCEDIR}/modelmesh/enable-uwm.yaml
}

function test_metrics() {
    header "Checking metrics for total number of runs, should be 1 since we have spun up 1 run"
    monitoring_token=$(oc create token prometheus-k8s -n openshift-monitoring)
    os::cmd::try_until_text "oc -n openshift-monitoring exec -c prometheus prometheus-k8s-0 -- curl -k -H \"Authorization: Bearer $monitoring_token\" 'https://thanos-querier.openshift-monitoring:9091/api/v1/query?query=run_server_run_count' | jq '.data.result[0].value[1]'" "1" $odhdefaulttimeout $odhdefaultinterval
}

function delete_runs() {
    header "Deleting runs"
    os::cmd::try_until_text "curl -s -X DELETE ${ROUTE}/apis/v1beta1/runs/${RUN_ID} | jq" "" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "curl -s ${ROUTE}/apis/v1beta1/runs/${RUN_ID} | jq '.code'" "5" $odhdefaulttimeout $odhdefaultinterval
}

function delete_pipeline() {
    header "Deleting the pipeline"
    os::cmd::try_until_text "curl -s -X DELETE ${ROUTE}/apis/v1beta1/pipelines/${PIPELINE_ID} | jq" "" $odhdefaulttimeout $odhdefaultinterval
}

check_resources
check_ui_overlay
create_pipeline
list_pipelines
create_run
list_runs
check_run_status
setup_monitoring
test_metrics
delete_runs
delete_pipeline
oc delete route ds-pipeline

os::test::junit::declare_suite_end
