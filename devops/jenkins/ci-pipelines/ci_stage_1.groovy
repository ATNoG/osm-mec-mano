/* Copyright 2017 Sandvine
 *
 * All Rights Reserved.
 * 
 *   Licensed under the Apache License, Version 2.0 (the "License"); you may
 *   not use this file except in compliance with the License. You may obtain
 *   a copy of the License at
 *
 *        http://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 *   WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 *   License for the specific language governing permissions and limitations
 *   under the License.
 */
/* Change log:
 * 1. Bug 699 : Jayant Madavi, Mrityunjay Yadav : JM00553988@techmahindra.com : 23-july-2019 : Improvement to the code, now using post syntax
 * 2. Jayant Madavi : 26-july-2019 : optimization to the previous check-in added currentBuild.result = 'SUCCESS'. TODO: code would be better *    if we use pipeline declarative 
 */
 
stage_3_merge_result = ''
def Get_MDG(project) {
    // split the project.
    def values = project.split('/')
    if ( values.size() > 1 ) {
        return values[1]
    }
    // no prefix, likely just the project name then
    return project
}

node("${params.NODE}") {

    mdg = Get_MDG("${GERRIT_PROJECT}")
    println("MDG is ${mdg}")

    if ( params.PROJECT_URL_PREFIX == null )
    {
        params.PROJECT_URL_PREFIX  = 'https://osm.etsi.org/gerrit'
    }

    stage('downstream') {
        // default to stage_2 (patchset)
        def stage_name = "stage_2"

        try {
            switch(GERRIT_EVENT_TYPE) {
                case "change-merged":
                   stage_name = "stage_2-merge"
                   break

                case "patchset-created":
                   stage_name = "stage_2"
                   break
            }
        }
        catch(caughtError) {
            println("No gerrit event found")
        }

        // pipeline running from gerrit trigger.
        // kickoff the downstream multibranch pipeline
        def downstream_params = [
            string(name: 'GERRIT_BRANCH', value: GERRIT_BRANCH),
            string(name: 'GERRIT_PROJECT', value: GERRIT_PROJECT),
            string(name: 'GERRIT_REFSPEC', value: GERRIT_REFSPEC),
            string(name: 'GERRIT_PATCHSET_REVISION', value: GERRIT_PATCHSET_REVISION),
            string(name: 'INSTALLER', value: params.INSTALLER),
            string(name: 'OPENSTACK_BASE_IMAGE', value: params.OPENSTACK_BASE_IMAGE),
            string(name: 'OPENSTACK_OSM_FLAVOR', value: params.OPENSTACK_OSM_FLAVOR),
            string(name: 'PROJECT_URL_PREFIX', value: params.PROJECT_URL_PREFIX),
            string(name: 'DOCKER_TAG', value: params.DOCKER_TAG),
            booleanParam(name: 'TEST_INSTALL', value: params.TEST_INSTALL),
            booleanParam(name: 'TRY_JUJU_INSTALLATION', value: params.TRY_JUJU_INSTALLATION),
            booleanParam(name: 'TRY_OLD_SERVICE_ASSURANCE', value: params.TRY_OLD_SERVICE_ASSURANCE),
        ]
        if ( params.DO_ROBOT )
        {
            downstream_params.add(booleanParam(name: 'DO_ROBOT', value: params.DO_ROBOT))
        }
        if ( params.ROBOT_TAG_NAME )
        {
            downstream_params.add(string(name: 'ROBOT_TAG_NAME', value: params.ROBOT_TAG_NAME))
        }

        if ( params.STAGE )
        {
            // go directly to stage 3 (osm system)
            stage_name = params.STAGE
            mdg = "osm"
            if ( ! params.TEST_INSTALL )
            {
                println("disabling stage_3 invocation")
                return
            }
            // in this case, since this is for daily jobs, the pass threshold for robot tests should be adapted
            downstream_params.add(string(name: 'ROBOT_PASS_THRESHOLD', value: '99.0'))
        }
        // callout to stage_2.  This is a multi-branch pipeline.
        downstream_job_name = "${mdg}-${stage_name}/${GERRIT_BRANCH}"

        println("Downstream job: ${downstream_job_name}")
        println("Downstream parameters: ${downstream_params}")
        currentBuild.result = 'SUCCESS'
        try {
            stage_3_merge_result = build job: "${downstream_job_name}", parameters: downstream_params, propagate: true
            if (stage_3_merge_result.getResult() != 'SUCCESS') {
                project = stage_3_merge_result.getProjectName()
                build = stage_3_merge_result.getNumber()
                // Jayant if the build fails the below error will cause the pipeline to terminate.
                // error("${project} build ${build} failed")
                currentBuild.result = stage_3_merge_result.getResult()
            }
        }
        catch(caughtError) {
            echo 'Exception in stage_1'
            currentBuild.result = 'FAILURE'
        }
        finally {
            try {
                if ((currentBuild.result != 'SUCCESS') && (env.JOB_NAME.startsWith('daily-stage_4'))){
                    emailext (
                        subject: "[OSM-Jenkins] Job: ${env.JOB_NAME} Build: ${env.BUILD_NUMBER} Result: ${currentBuild.result}",
                        body: """ Check console output at "${env.BUILD_URL}"  """,
                        to: 'OSM_MDL@list.etsi.org',
                        recipientProviders: [culprits()]
                    )
                }
            }
            catch(caughtError) {
                echo "Failure in executing email"
            }
        }
    }
}

