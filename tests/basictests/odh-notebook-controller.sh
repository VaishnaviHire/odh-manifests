#!/bin/bash

source $TEST_DIR/common

MY_DIR=$(readlink -f `dirname "${BASH_SOURCE[0]}"`)

source ${MY_DIR}/../util

NOTEBOOKS_DIR="${MY_DIR}/../resources/notebook-controller/notebooks"

os::test::junit::declare_suite_start "$MY_SCRIPT"

function test_notebook_controller() {
    header "Testing Notebook Controller installation"

    # Switch to opendatahub project
    os::cmd::expect_success "oc project ${ODHPROJECT}"

    # Verify Kubeflow Notebook Controller installation
    test_kubeflow_notebook_controller

    # Verify ODH Notebook Controller installation
    test_odh_notebook_controller

    # Test the creation and deletion of notebooks in the NOTEBOOKS_DIR folder
    for notebook_path in ${NOTEBOOKS_DIR}/*.yaml; do
        notebook_name="$(basename "${notebook_path}" .yaml)"
        test_notebook_creation ${notebook_path} ${notebook_name}
        test_notebook_deletion ${notebook_path} ${notebook_name}
    done
}

function test_kubeflow_notebook_controller() {
    header "Testing Kubeflow Notebook Controller deployment"
    # Verify the controller is running
    os::cmd::try_until_text "oc get deployment/notebook-controller-deployment" "notebook-controller-deployment" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "oc rollout status deployment/notebook-controller-deployment -w=false" "successfully rolled out" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "oc get pods -l app=notebook-controller --field-selector='status.phase=Running' -o jsonpath='{$.items[*].metadata.name}'" "notebook-controller-deployment" ${odhdefaulttimeout} ${odhdefaultinterval}
    # Verify the number of pods runnings is 1
    runningpods=($(oc get pods -l app=notebook-controller --field-selector="status.phase=Running" -o jsonpath="{$.items[*].metadata.name}"))
    os::cmd::expect_success_and_text "echo ${#runningpods[@]}" "1"
}

function test_odh_notebook_controller() {
    header "Testing ODH Notebook Controller deployment"
    # Verify the controller is running
    os::cmd::try_until_text "oc get deployment/odh-notebook-controller-manager" "odh-notebook-controller-manager" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "oc rollout status deployment/odh-notebook-controller-manager -w=false" "successfully rolled out" $odhdefaulttimeout $odhdefaultinterval
    os::cmd::try_until_text "oc get pods -l app=odh-notebook-controller --field-selector='status.phase=Running' -o jsonpath='{$.items[*].metadata.name}'" "odh-notebook-controller-manager" ${odhdefaulttimeout} ${odhdefaultinterval}
    # Verify the number of pods runnings is 1
    runningpods=($(oc get pods -l app=odh-notebook-controller --field-selector="status.phase=Running" -o jsonpath="{$.items[*].metadata.name}"))
    os::cmd::expect_success_and_text "echo ${#runningpods[@]}" "1"
}

function test_notebook_creation() {
    header "Creating ${2} notebook"
    local notebook_path=${1}
    local notebook_name=${2}
    # Create notebook resources
    os::cmd::expect_success "oc apply -f ${notebook_path}"
    # Verify notebook CR exists
    os::cmd::try_until_text "oc get notebook ${notebook_name}" "${notebook_name}" $odhdefaulttimeout $odhdefaultinterval
    # Verify notebook STS is created
    os::cmd::try_until_text "oc get statefulset ${notebook_name}" "${notebook_name}" $odhdefaulttimeout $odhdefaultinterval
    # Verify notebook Pod is running
    os::cmd::try_until_text "oc get pods -l notebook-name=${notebook_name} --field-selector='status.phase=Running' -o jsonpath='{$.items[*].metadata.name}'" "${notebook_name}-0" $odhdefaulttimeout $odhdefaultinterval
}

function test_notebook_deletion() {
    header "Cleaning up ${2} notebook"
    local notebook_path=${1}
    local notebook_name=${2}
    # Delete the notebook object
    os::cmd::expect_success "oc delete -f ${notebook_path}"
    # Verify the notebook CR does not exist anymore
    os::cmd::try_until_text "oc get notebook ${notebook_name}" "not found" $odhdefaulttimeout $odhdefaultinterval
    # Verify the notebook STS is deleted
    os::cmd::try_until_text "oc get statefulset ${notebook_name}" "not found" $odhdefaulttimeout $odhdefaultinterval
    # Verify the notebook Pod is not running anymore
    os::cmd::try_until_text "oc get pods -l notebook-name=${notebook_name}" "No resources found" $odhdefaulttimeout $odhdefaultinterval
    # Verify the notebook Route is deleted
    os::cmd::try_until_text "oc get route ${notebook_name}" "not found" $odhdefaulttimeout $odhdefaultinterval
}

function gather_notebook_controller_logs() {
    echo "Saving the logs from the kf-notebook-controller pod in the artifacts directory"
    oc logs -l app=notebook-controller --all-containers --tail=-1 -n ${ODHPROJECT} \
        > ${ARTIFACT_DIR}/kf-notebook-controller.log 2> /dev/null || echo "No logs for ${ODHPROJECT}/kf-notebook-controller"

    echo "Saving the logs from the odh-notebook-controller pod in the artifacts directory"
    oc logs -l app=odh-notebook-controller --all-containers --tail=-1 -n ${ODHPROJECT} \
        > ${ARTIFACT_DIR}/odh-notebook-controller.log 2> /dev/null || echo "No logs for ${ODHPROJECT}/odh-notebook-controller"
}

test_notebook_controller

os::test::junit::declare_suite_end

gather_notebook_controller_logs
