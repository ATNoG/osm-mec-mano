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

def project_checkout(url_prefix,project,refspec,revision) {
    // checkout the project
    // this is done automaticaly by the multibranch pipeline plugin
    // git url: "${url_prefix}/${project}"

    sh "git fetch --tags"
    sh "git fetch origin ${refspec}"
    if (GERRIT_PATCHSET_REVISION.size() > 0 ) {
        sh "git checkout -f ${revision}"
    }
    sh "sudo git clean -dfx"
}

def ci_pipeline(mdg,url_prefix,project,branch,refspec,revision,do_stage_3,artifactory_server,docker_args="",do_stage_4=false) {
    println("do_stage_3= ${do_stage_3}")
    ci_helper = load "devops/jenkins/ci-pipelines/ci_helper.groovy"
    def isMergeJob = JOB_NAME.contains('merge')

    stage('Prepare') {
        sh 'env'
    }

    stage('Checkout') {
        project_checkout(url_prefix,project,refspec,revision)
    }

    stage('License Scan') {
      if (!isMergeJob) {
        sh "devops/tools/license_scan.sh"
      }
      else {
        println("skip the scan for merge")
      }
    }

    stage('Release Note Check') {
      if (fileExists('devops-stages/stage-releasenote.sh')) {
        if (!isMergeJob) {
            sh "devops-stages/stage-releasenote.sh"
        }
        else {
            println("Not checking release notes for merge job")
        }
      }
      else {
          println("No releasenote check present")
      }
    }

    container_name = "${project}-${branch}".toLowerCase()

    stage('Docker-Build') {
        APT_PROXY = "http://172.21.1.1:3142"
        sh "docker build --build-arg APT_PROXY=${APT_PROXY} -t ${container_name} ."
    }

    UID = sh(returnStdout:true,  script: 'id -u').trim()
    GID = sh(returnStdout:true,  script: 'id -g').trim()
    withDockerContainer(image: "${container_name}", args: docker_args + " -u root") {
        stage('Test') {
            sh "groupadd -o -g $GID -r jenkins"
            sh "useradd -o -u $UID -d `pwd` -r -g jenkins jenkins"
            sh "echo '#! /bin/sh' > /usr/bin/mesg"
            sh "chmod 755 /usr/bin/mesg"
            sh "runuser jenkins -c devops-stages/stage-test.sh"
            if (fileExists('coverage.xml')) {
                cobertura coberturaReportFile: 'coverage.xml'
            }
            if (fileExists('nosetests.xml')) {
                junit 'nosetests.xml'
            }
        }
        stage('Build') {
            sh(returnStdout:true,
                script: "runuser jenkins -c devops-stages/stage-build.sh").trim()
        }
        stage('Archive') {
            sh "runuser jenkins -c 'mkdir -p changelog'"
            sh "runuser jenkins -c \"devops/tools/generatechangelog-pipeline.sh > changelog/changelog-${mdg}.html\""
            sh(returnStdout:true,
                script: "runuser jenkins -c devops-stages/stage-archive.sh").trim()
            ci_helper.archive(artifactory_server,mdg,branch,'untested')
        }
    }

    if ( do_stage_3 ) {
        stage('Build System') {
            def downstream_params_stage_3 = [
                string(name: 'GERRIT_BRANCH', value: "${branch}"),
                string(name: 'INSTALLER', value: "Default" ),
                string(name: 'OPENSTACK_BASE_IMAGE', value: "ubuntu22.04" ),
                string(name: 'OPENSTACK_OSM_FLAVOR', value: "osm.sanity" ),
                string(name: 'UPSTREAM_JOB_NAME', value: "${JOB_NAME}" ),
                string(name: 'UPSTREAM_JOB_NUMBER', value: "${BUILD_NUMBER}" ),
                booleanParam(name: 'DO_STAGE_4', value: do_stage_4 ),
                booleanParam(name: 'TRY_JUJU_INSTALLATION', value: false),
                booleanParam(name: 'TRY_OLD_SERVICE_ASSURANCE', value: false),
            ]
            stage_3_job = "osm-stage_3"
            if ( JOB_NAME.contains('merge') ) {
                stage_3_job += '-merge'
            }

            // callout to stage_3. This is the system build
            result = build job: "${stage_3_job}/${branch}", parameters: downstream_params_stage_3, propagate: true
            if (result.getResult() != 'SUCCESS') {
                project = result.getProjectName()
                build = result.getNumber()
                error("${project} build ${build} failed")
            }
        }
    }
}

return this
