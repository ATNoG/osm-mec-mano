/* Copyright ETSI Contributors and Others
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

properties([
    parameters([
        string(defaultValue: env.GERRIT_BRANCH, description: '', name: 'GERRIT_BRANCH'),
        string(defaultValue: 'system', description: '', name: 'NODE'),
        string(defaultValue: '', description: '', name: 'BUILD_FROM_SOURCE'),
        string(defaultValue: 'unstable', description: '', name: 'REPO_DISTRO'),
        string(defaultValue: '', description: '', name: 'COMMIT_ID'),
        string(defaultValue: '-stage_2', description: '', name: 'UPSTREAM_SUFFIX'),
        string(defaultValue: 'pubkey.asc', description: '', name: 'REPO_KEY_NAME'),
        string(defaultValue: 'release', description: '', name: 'RELEASE'),
        string(defaultValue: '', description: '', name: 'UPSTREAM_JOB_NAME'),
        string(defaultValue: '', description: '', name: 'UPSTREAM_JOB_NUMBER'),
        string(defaultValue: 'OSMETSI', description: '', name: 'GPG_KEY_NAME'),
        string(defaultValue: 'artifactory-osm', description: '', name: 'ARTIFACTORY_SERVER'),
        string(defaultValue: 'osm-stage_4', description: '', name: 'DOWNSTREAM_STAGE_NAME'),
        string(defaultValue: 'testing-daily', description: '', name: 'DOCKER_TAG'),
        string(defaultValue: 'ubuntu22.04', description: '', name: 'OPENSTACK_BASE_IMAGE'),
        string(defaultValue: 'osm.sanity', description: '', name: 'OPENSTACK_OSM_FLAVOR'),
        booleanParam(defaultValue: false, description: '', name: 'TRY_OLD_SERVICE_ASSURANCE'),
        booleanParam(defaultValue: true, description: '', name: 'TRY_JUJU_INSTALLATION'),
        booleanParam(defaultValue: false, description: '', name: 'SAVE_CONTAINER_ON_FAIL'),
        booleanParam(defaultValue: false, description: '', name: 'SAVE_CONTAINER_ON_PASS'),
        booleanParam(defaultValue: true, description: '', name: 'SAVE_ARTIFACTS_ON_SMOKE_SUCCESS'),
        booleanParam(defaultValue: true, description: '',  name: 'DO_BUILD'),
        booleanParam(defaultValue: true, description: '', name: 'DO_INSTALL'),
        booleanParam(defaultValue: true, description: '', name: 'DO_DOCKERPUSH'),
        booleanParam(defaultValue: false, description: '', name: 'SAVE_ARTIFACTS_OVERRIDE'),
        string(defaultValue: '/home/jenkins/hive/openstack-etsi.rc', description: '', name: 'HIVE_VIM_1'),
        booleanParam(defaultValue: true, description: '', name: 'DO_ROBOT'),
        string(defaultValue: 'sanity', description: 'sanity/regression/daily are the common options',
               name: 'ROBOT_TAG_NAME'),
        string(defaultValue: '/home/jenkins/hive/robot-systest.cfg', description: '', name: 'ROBOT_VIM'),
        string(defaultValue: '/home/jenkins/hive/port-mapping-etsi-vim.yaml',
               description: 'Port mapping file for SDN assist in ETSI VIM',
               name: 'ROBOT_PORT_MAPPING_VIM'),
        string(defaultValue: '/home/jenkins/hive/kubeconfig.yaml', description: '', name: 'KUBECONFIG'),
        string(defaultValue: '/home/jenkins/hive/clouds.yaml', description: '', name: 'CLOUDS'),
        string(defaultValue: 'Default', description: '', name: 'INSTALLER'),
        string(defaultValue: '100.0', description: '% passed Robot tests to mark the build as passed',
               name: 'ROBOT_PASS_THRESHOLD'),
        string(defaultValue: '80.0', description: '% passed Robot tests to mark the build as unstable ' +
               '(if lower, it will be failed)', name: 'ROBOT_UNSTABLE_THRESHOLD'),
    ])
])

////////////////////////////////////////////////////////////////////////////////////////
// Helper Functions
////////////////////////////////////////////////////////////////////////////////////////
void run_robot_systest(String tagName,
                       String testName,
                       String osmHostname,
                       String prometheusHostname,
                       Integer prometheusPort=null,
                       String ociRegistryUrl,
                       String envfile=null,
                       String portmappingfile=null,
                       String kubeconfig=null,
                       String clouds=null,
                       String hostfile=null,
                       String jujuPassword=null,
                       String osmRSAfile=null,
                       String passThreshold='0.0',
                       String unstableThreshold='0.0') {
    tempdir = sh(returnStdout: true, script: 'mktemp -d').trim()
    String environmentFile = ''
    if (envfile) {
        environmentFile = envfile
    } else {
        sh(script: "touch ${tempdir}/env")
        environmentFile = "${tempdir}/env"
    }
    PROMETHEUS_PORT_VAR = ''
    if (prometheusPort != null) {
        PROMETHEUS_PORT_VAR = "--env PROMETHEUS_PORT=${prometheusPort}"
    }
    hostfilemount = ''
    if (hostfile) {
        hostfilemount = "-v ${hostfile}:/etc/hosts"
    }

    JUJU_PASSWORD_VAR = ''
    if (jujuPassword != null) {
        JUJU_PASSWORD_VAR = "--env JUJU_PASSWORD=${jujuPassword}"
    }

    try {
        withCredentials([usernamePassword(credentialsId: 'gitlab-oci-test', 
                        passwordVariable: 'OCI_REGISTRY_PSW', usernameVariable: 'OCI_REGISTRY_USR')]) {
            sh("""docker run --env OSM_HOSTNAME=${osmHostname} --env PROMETHEUS_HOSTNAME=${prometheusHostname} \
               ${PROMETHEUS_PORT_VAR} ${JUJU_PASSWORD_VAR} --env-file ${environmentFile} \
               --env OCI_REGISTRY_URL=${ociRegistryUrl} --env OCI_REGISTRY_USER=${OCI_REGISTRY_USR} \
               --env OCI_REGISTRY_PASSWORD=${OCI_REGISTRY_PSW} \
               -v ${clouds}:/etc/openstack/clouds.yaml -v ${osmRSAfile}:/root/osm_id_rsa \
               -v ${kubeconfig}:/root/.kube/config -v ${tempdir}:/robot-systest/reports \
               -v ${portmappingfile}:/root/port-mapping.yaml ${hostfilemount} opensourcemano/tests:${tagName} \
               -c -t ${testName}""")
        }
    } finally {
        try {
            sh("cp ${tempdir}/*.xml .")
            sh("cp ${tempdir}/*.html .")
            outputDirectory = sh(returnStdout: true, script: 'pwd').trim()
            println("Present Directory is : ${outputDirectory}")
            sh("tree ${outputDirectory}")
        } catch (Exception e) {
            println("Something happened during the execution of shell script: ${e.message}")
        }

        println("Continue with the publication of Robot results...")
        println("passThreshold: ${passThreshold}")
        println("unstableThreshold: ${unstableThreshold}")
        step([
            $class : 'RobotPublisher',
            outputPath : "${outputDirectory}",
            outputFileName : '*.xml',
            disableArchiveOutput : false,
            reportFileName : 'report.html',
            logFileName : 'log.html',
            passThreshold : passThreshold,
            unstableThreshold: unstableThreshold,
            otherFiles : '*.png',
        ])
        println("Robot reports were correctly published by RobotPublisher")
    }
}

void archive_logs(Map remote) {

    sshCommand remote: remote, command: '''mkdir -p logs/dags'''
    if (useCharmedInstaller) {
        sshCommand remote: remote, command: '''
            for pod in `kubectl get pods -n osm | grep -v operator | grep -v NAME| awk '{print $1}'`; do
                logfile=`echo $pod | cut -d- -f1`
                echo "Extracting log for $logfile"
                kubectl logs -n osm $pod --timestamps=true 2>&1 > logs/$logfile.log
            done
        '''
    } else {
        sshCommand remote: remote, command: '''
            for deployment in `kubectl -n osm get deployments | grep -v operator | grep -v NAME| awk '{print $1}'`; do
                echo "Extracting log for $deployment"
                kubectl -n osm logs deployments/$deployment --timestamps=true --all-containers 2>&1 \
                > logs/$deployment.log
            done
        '''
        sshCommand remote: remote, command: '''
            for statefulset in `kubectl -n osm get statefulsets | grep -v operator | grep -v NAME| awk '{print $1}'`; do
                echo "Extracting log for $statefulset"
                kubectl -n osm logs statefulsets/$statefulset --timestamps=true --all-containers 2>&1 \
                > logs/$statefulset.log
            done
        '''
        sshCommand remote: remote, command: '''
            schedulerPod="$(kubectl get pods -n osm | grep airflow-scheduler| awk '{print $1; exit}')"; \
            echo "Extracting logs from Airflow DAGs from pod ${schedulerPod}"; \
            kubectl cp -n osm ${schedulerPod}:/opt/airflow/logs/scheduler/latest/dags logs/dags -c scheduler
        '''
    }

    sh 'rm -rf logs'
    sshCommand remote: remote, command: '''ls -al logs'''
    sshGet remote: remote, from: 'logs', into: '.', override: true
    archiveArtifacts artifacts: 'logs/*.log, logs/dags/*.log'
}

String get_value(String key, String output) {
    for (String line : output.split( '\n' )) {
        data = line.split( '\\|' )
        if (data.length > 1) {
            if ( data[1].trim() == key ) {
                return data[2].trim()
            }
        }
    }
}

////////////////////////////////////////////////////////////////////////////////////////
// Main Script
////////////////////////////////////////////////////////////////////////////////////////
node("${params.NODE}") {

    INTERNAL_DOCKER_REGISTRY = 'osm.etsi.org:5050/devops/cicd/'
    INTERNAL_DOCKER_PROXY = 'http://172.21.1.1:5000'
    APT_PROXY = 'http://172.21.1.1:3142'
    SSH_KEY = '~/hive/cicd_rsa'
    ARCHIVE_LOGS_FLAG = false
    OCI_REGISTRY_URL = 'oci://osm.etsi.org:5050/devops/test'
    sh 'env'

    tag_or_branch = params.GERRIT_BRANCH.replaceAll(/\./, '')

    stage('Checkout') {
        checkout scm
    }

    ci_helper = load 'jenkins/ci-pipelines/ci_helper.groovy'

    def upstreamMainJob = params.UPSTREAM_SUFFIX

    // upstream jobs always use merged artifacts
    upstreamMainJob += '-merge'
    containerNamePrefix = "osm-${tag_or_branch}"
    containerName = "${containerNamePrefix}"

    keep_artifacts = false
    if ( JOB_NAME.contains('merge') ) {
        containerName += '-merge'

        // On a merge job, we keep artifacts on smoke success
        keep_artifacts = params.SAVE_ARTIFACTS_ON_SMOKE_SUCCESS
    }
    containerName += "-${BUILD_NUMBER}"

    server_id = null
    http_server_name = null
    devopstempdir = null
    useCharmedInstaller = params.INSTALLER.equalsIgnoreCase('charmed')

    try {
        builtModules = [:]
///////////////////////////////////////////////////////////////////////////////////////
// Fetch stage 2 .deb artifacts
///////////////////////////////////////////////////////////////////////////////////////
        stage('Copy Artifacts') {
            // cleanup any previous repo
            sh "tree -fD repo || exit 0"
            sh 'rm -rvf repo'
            sh "tree -fD repo && lsof repo || exit 0"
            dir('repo') {
                packageList = []
                dir("${RELEASE}") {
                    RELEASE_DIR = sh(returnStdout:true,  script: 'pwd').trim()

                    // check if an upstream artifact based on specific build number has been requested
                    // This is the case of a merge build and the upstream merge build is not yet complete
                    // (it is not deemed a successful build yet). The upstream job is calling this downstream
                    // job (with the its build artifact)
                    def upstreamComponent = ''
                    if (params.UPSTREAM_JOB_NAME) {
                        println("Fetching upstream job artifact from ${params.UPSTREAM_JOB_NAME}")
                        lock('Artifactory') {
                            step ([$class: 'CopyArtifact',
                                projectName: "${params.UPSTREAM_JOB_NAME}",
                                selector: [$class: 'SpecificBuildSelector',
                                buildNumber: "${params.UPSTREAM_JOB_NUMBER}"]
                                ])

                            upstreamComponent = ci_helper.get_mdg_from_project(
                                ci_helper.get_env_value('build.env','GERRIT_PROJECT'))
                            def buildNumber = ci_helper.get_env_value('build.env','BUILD_NUMBER')
                            dir("$upstreamComponent") {
                                // the upstream job name contains suffix with the project. Need this stripped off
                                project_without_branch = params.UPSTREAM_JOB_NAME.split('/')[0]
                                packages = ci_helper.get_archive(params.ARTIFACTORY_SERVER,
                                    upstreamComponent,
                                    GERRIT_BRANCH,
                                    "${project_without_branch} :: ${GERRIT_BRANCH}",
                                    buildNumber)

                                packageList.addAll(packages)
                                println("Fetched pre-merge ${params.UPSTREAM_JOB_NAME}: ${packages}")
                            }
                        } // lock artifactory
                    }

                    parallelSteps = [:]
                    list = ['RO', 'osmclient', 'IM', 'devops', 'MON', 'N2VC', 'NBI',
                            'common', 'LCM', 'POL', 'NG-UI', 'NG-SA', 'PLA', 'tests']
                    if (upstreamComponent.length() > 0) {
                        println("Skipping upstream fetch of ${upstreamComponent}")
                        list.remove(upstreamComponent)
                    }
                    for (buildStep in list) {
                        def component = buildStep
                        parallelSteps[component] = {
                            dir("$component") {
                                println("Fetching artifact for ${component}")
                                step([$class: 'CopyArtifact',
                                       projectName: "${component}${upstreamMainJob}/${GERRIT_BRANCH}"])

                                // grab the archives from the stage_2 builds
                                // (ie. this will be the artifacts stored based on a merge)
                                packages = ci_helper.get_archive(params.ARTIFACTORY_SERVER,
                                    component,
                                    GERRIT_BRANCH,
                                    "${component}${upstreamMainJob} :: ${GERRIT_BRANCH}",
                                    ci_helper.get_env_value('build.env', 'BUILD_NUMBER'))
                                packageList.addAll(packages)
                                println("Fetched ${component}: ${packages}")
                                sh 'rm -rf dists'
                            }
                        }
                    }
                    lock('Artifactory') {
                        parallel parallelSteps
                    }

///////////////////////////////////////////////////////////////////////////////////////
// Create Devops APT repository
///////////////////////////////////////////////////////////////////////////////////////
                    sh 'mkdir -p pool'
                    for (component in [ 'devops', 'IM', 'osmclient' ]) {
                        sh "ls -al ${component}/pool/"
                        sh "cp -r ${component}/pool/* pool/"
                        sh "dpkg-sig --sign builder -k ${GPG_KEY_NAME} pool/${component}/*"
                        sh "mkdir -p dists/${params.REPO_DISTRO}/${component}/binary-amd64/"
                        sh("""apt-ftparchive packages pool/${component} \
                           > dists/${params.REPO_DISTRO}/${component}/binary-amd64/Packages""")
                        sh "gzip -9fk dists/${params.REPO_DISTRO}/${component}/binary-amd64/Packages"
                    }

                    // create and sign the release file
                    sh "apt-ftparchive release dists/${params.REPO_DISTRO} > dists/${params.REPO_DISTRO}/Release"
                    sh("""gpg --yes -abs -u ${GPG_KEY_NAME} \
                       -o dists/${params.REPO_DISTRO}/Release.gpg dists/${params.REPO_DISTRO}/Release""")

                    // copy the public key into the release folder
                    // this pulls the key from the home dir of the current user (jenkins)
                    sh "cp ~/${REPO_KEY_NAME} 'OSM ETSI Release Key.gpg'"
                    sh "cp ~/${REPO_KEY_NAME} ."
                }

                // start an apache server to serve up the packages
                http_server_name = "${containerName}-apache"

                pwd = sh(returnStdout:true,  script: 'pwd').trim()
                repo_port = sh(script: 'echo $(python -c \'import socket; s=socket.socket(); s.bind(("", 0));' +
                               'print(s.getsockname()[1]); s.close()\');',
                               returnStdout: true).trim()
                internal_docker_http_server_url = ci_helper.start_http_server(pwd, http_server_name, repo_port)
                NODE_IP_ADDRESS = sh(returnStdout: true, script:
                    "echo ${SSH_CONNECTION} | awk '{print \$3}'").trim()
                ci_helper.check_status_http_server(NODE_IP_ADDRESS, repo_port)
            }

            sh "tree -fD repo"

            // Unpack devops package into temporary location so that we use it from upstream if it was part of a patch
            osm_devops_dpkg = sh(returnStdout: true, script: 'find ./repo/release/pool/ -name osm-devops*.deb').trim()
            devopstempdir = sh(returnStdout: true, script: 'mktemp -d').trim()
            println("Extracting local devops package ${osm_devops_dpkg} into ${devopstempdir} for docker build step")
            sh "dpkg -x ${osm_devops_dpkg} ${devopstempdir}"
            OSM_DEVOPS = "${devopstempdir}/usr/share/osm-devops"
            // Convert URLs from stage 2 packages to arguments that can be passed to docker build
            for (remotePath in packageList) {
                packageName = remotePath[remotePath.lastIndexOf('/') + 1 .. -1]
                packageName = packageName[0 .. packageName.indexOf('_') - 1]
                builtModules[packageName] = remotePath
            }
        }

///////////////////////////////////////////////////////////////////////////////////////
// Build docker containers
///////////////////////////////////////////////////////////////////////////////////////
        dir(OSM_DEVOPS) {
            Map remote = [:]
            error = null
            if ( params.DO_BUILD ) {
                withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'gitlab-registry',
                                usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD']]) {
                    sh "docker login ${INTERNAL_DOCKER_REGISTRY} -u ${USERNAME} -p ${PASSWORD}"
                }
                datetime = sh(returnStdout: true, script: 'date +%Y-%m-%d:%H:%M:%S').trim()
                moduleBuildArgs = " --build-arg CACHE_DATE=${datetime}"
                for (packageName in builtModules.keySet()) {
                    envName = packageName.replaceAll('-', '_').toUpperCase() + '_URL'
                    moduleBuildArgs += " --build-arg ${envName}=" + builtModules[packageName]
                }
                dir('docker') {
                    stage('Build') {
                        containerList = sh(returnStdout: true, script:
                            "find . -name Dockerfile -printf '%h\\n' | sed 's|\\./||'")
                        containerList = Arrays.asList(containerList.split('\n'))
                        print(containerList)
                        parallelSteps = [:]
                        for (buildStep in containerList) {
                            def module = buildStep
                            def moduleName = buildStep.toLowerCase()
                            def moduleTag = containerName
                            parallelSteps[module] = {
                                dir("$module") {
                                    sh("""docker build --build-arg APT_PROXY=${APT_PROXY} \
                                    -t opensourcemano/${moduleName}:${moduleTag} ${moduleBuildArgs} .""")
                                    println("Tagging ${moduleName}:${moduleTag}")
                                    sh("""docker tag opensourcemano/${moduleName}:${moduleTag} \
                                    ${INTERNAL_DOCKER_REGISTRY}opensourcemano/${moduleName}:${moduleTag}""")
                                    sh("""docker push \
                                    ${INTERNAL_DOCKER_REGISTRY}opensourcemano/${moduleName}:${moduleTag}""")
                                }
                            }
                        }
                        parallel parallelSteps
                    }
                }
            } // if (params.DO_BUILD)

            if (params.DO_INSTALL) {
///////////////////////////////////////////////////////////////////////////////////////
// Launch VM
///////////////////////////////////////////////////////////////////////////////////////
                stage('Spawn Remote VM') {
                    println('Launching new VM')
                    output = sh(returnStdout: true, script: """#!/bin/sh -e
                        for line in `grep OS ~/hive/robot-systest.cfg | grep -v OS_CLOUD` ; do export \$line ; done
                        openstack server create --flavor ${OPENSTACK_OSM_FLAVOR} \
                                                --image ${OPENSTACK_BASE_IMAGE} \
                                                --key-name CICD \
                                                --property build_url="${BUILD_URL}" \
                                                --nic net-id=osm-ext \
                                                ${containerName}
                    """).trim()

                    server_id = get_value('id', output)

                    if (server_id == null) {
                        println('VM launch output: ')
                        println(output)
                        throw new Exception('VM Launch failed')
                    }
                    println("Target VM is ${server_id}, waiting for IP address to be assigned")

                    IP_ADDRESS = ''

                    while (IP_ADDRESS == '') {
                        output = sh(returnStdout: true, script: """#!/bin/sh -e
                            for line in `grep OS ~/hive/robot-systest.cfg | grep -v OS_CLOUD` ; do export \$line ; done
                            openstack server show ${server_id}
                        """).trim()
                        IP_ADDRESS = get_value('addresses', output)
                    }
                    IP_ADDRESS = IP_ADDRESS.split('=')[1]
                    println("Waiting for VM at ${IP_ADDRESS} to be reachable")

                    alive = false
                    timeout(time: 1, unit: 'MINUTES') {
                        while (!alive) {
                            output = sh(
                                returnStatus: true,
                                script: "ssh -T -i ${SSH_KEY} " +
                                    "-o StrictHostKeyChecking=no " +
                                    "-o UserKnownHostsFile=/dev/null " +
                                    "-o ConnectTimeout=5 ubuntu@${IP_ADDRESS} 'echo Alive'")
                            alive = (output == 0)
                        }
                    }
                    println('VM is ready and accepting ssh connections')

                    //////////////////////////////////////////////////////////////////////////////////////////////
                    println('Applying sshd config workaround for Ubuntu 22.04 and old jsch client in Jenkins...')

                    sh( returnStatus: true,
                        script: "ssh -T -i ${SSH_KEY} " +
                            "-o StrictHostKeyChecking=no " +
                            "-o UserKnownHostsFile=/dev/null " +
                            "ubuntu@${IP_ADDRESS} " +
                            "'echo HostKeyAlgorithms +ssh-rsa | sudo tee -a /etc/ssh/sshd_config'")
                    sh( returnStatus: true,
                        script: "ssh -T -i ${SSH_KEY} " +
                            "-o StrictHostKeyChecking=no " +
                            "-o UserKnownHostsFile=/dev/null " +
                            "ubuntu@${IP_ADDRESS} " +
                            "'echo PubkeyAcceptedKeyTypes +ssh-rsa | sudo tee -a /etc/ssh/sshd_config'")
                    sh( returnStatus: true,
                        script: "ssh -T -i ${SSH_KEY} " +
                            "-o StrictHostKeyChecking=no " +
                            "-o UserKnownHostsFile=/dev/null " +
                            "ubuntu@${IP_ADDRESS} " +
                            "'sudo systemctl restart sshd'")
                    //////////////////////////////////////////////////////////////////////////////////////////////

                } // stage("Spawn Remote VM")

///////////////////////////////////////////////////////////////////////////////////////
// Checks before installation
///////////////////////////////////////////////////////////////////////////////////////
                stage('Checks before installation') {
                    remote = [
                        name: containerName,
                        host: IP_ADDRESS,
                        user: 'ubuntu',
                        identityFile: SSH_KEY,
                        allowAnyHosts: true,
                        logLevel: 'INFO',
                        pty: true
                    ]

                    // Ensure the VM is ready
                    sshCommand remote: remote, command: 'cloud-init status --wait'
                    // Force time sync to avoid clock drift and invalid certificates
                    sshCommand remote: remote, command: 'sudo apt-get -y update'
                    sshCommand remote: remote, command: 'sudo apt-get -y install chrony'
                    sshCommand remote: remote, command: 'sudo service chrony stop'
                    sshCommand remote: remote, command: 'sudo chronyd -vq'
                    sshCommand remote: remote, command: 'sudo service chrony start'

                 } // stage("Checks before installation")
///////////////////////////////////////////////////////////////////////////////////////
// Installation
///////////////////////////////////////////////////////////////////////////////////////
                stage('Install') {
                    commit_id = ''
                    repo_distro = ''
                    repo_key_name = ''
                    release = ''

                    if (params.COMMIT_ID) {
                        commit_id = "-b ${params.COMMIT_ID}"
                    }
                    if (params.REPO_DISTRO) {
                        repo_distro = "-r ${params.REPO_DISTRO}"
                    }
                    if (params.REPO_KEY_NAME) {
                        repo_key_name = "-k ${params.REPO_KEY_NAME}"
                    }
                    if (params.RELEASE) {
                        release = "-R ${params.RELEASE}"
                    }
                    if (params.REPOSITORY_BASE) {
                        repo_base_url = "-u ${params.REPOSITORY_BASE}"
                    } else {
                        repo_base_url = "-u http://${NODE_IP_ADDRESS}:${repo_port}"
                    }

                    remote = [
                        name: containerName,
                        host: IP_ADDRESS,
                        user: 'ubuntu',
                        identityFile: SSH_KEY,
                        allowAnyHosts: true,
                        logLevel: 'INFO',
                        pty: true
                    ]

                    sshCommand remote: remote, command: '''
                        wget https://osm-download.etsi.org/ftp/osm-17.0-seventeen/install_osm.sh
                        chmod +x ./install_osm.sh
                        sed -i '1 i\\export PATH=/snap/bin:\$PATH' ~/.bashrc
                    '''

                    Map gitlabCredentialsMap = [$class: 'UsernamePasswordMultiBinding',
                                                credentialsId: 'gitlab-registry',
                                                usernameVariable: 'USERNAME',
                                                passwordVariable: 'PASSWORD']
                    if (useCharmedInstaller) {
                        // Use local proxy for docker hub
                        sshCommand remote: remote, command: '''
                            sudo snap install microk8s --classic --channel=1.19/stable
                            sudo sed -i "s|https://registry-1.docker.io|http://172.21.1.1:5000|" \
                            /var/snap/microk8s/current/args/containerd-template.toml
                            sudo systemctl restart snap.microk8s.daemon-containerd.service
                            sudo snap alias microk8s.kubectl kubectl
                        '''

                        withCredentials([gitlabCredentialsMap]) {
                            sshCommand remote: remote, command: """
                                ./install_osm.sh -y \
                                    ${repo_base_url} \
                                    ${repo_key_name} \
                                    ${release} -r unstable \
                                    --charmed  \
                                    --registry ${USERNAME}:${PASSWORD}@${INTERNAL_DOCKER_REGISTRY} \
                                    --tag ${containerName}
                            """
                        }
                        prometheusHostname = "prometheus.${IP_ADDRESS}.nip.io"
                        prometheusPort = 80
                        osmHostname = "nbi.${IP_ADDRESS}.nip.io:443"
                    } else {
                        // Run -k8s installer here specifying internal docker registry and docker proxy
                        osm_installation_options = ""
                        if (params.TRY_OLD_SERVICE_ASSURANCE) {
                            osm_installation_options = "${osm_installation_options} --old-sa"
                        }
                        if (params.TRY_JUJU_INSTALLATION) {
                            osm_installation_options = "${osm_installation_options} --juju --lxd"
                        }
                        withCredentials([gitlabCredentialsMap]) {
                            sshCommand remote: remote, command: """
                                ./install_osm.sh -y \
                                    ${repo_base_url} \
                                    ${repo_key_name} \
                                    ${release} -r unstable \
                                    -d ${USERNAME}:${PASSWORD}@${INTERNAL_DOCKER_REGISTRY} \
                                    -p ${INTERNAL_DOCKER_PROXY} \
                                    -t ${containerName} \
                                    ${osm_installation_options}
                            """
                        }
                        prometheusHostname = "prometheus.${IP_ADDRESS}.nip.io"
                        prometheusPort = 80
                        osmHostname = "nbi.${IP_ADDRESS}.nip.io:443"
                    }
                } // stage("Install")
///////////////////////////////////////////////////////////////////////////////////////
// Health check of installed OSM in remote vm
///////////////////////////////////////////////////////////////////////////////////////
                stage('OSM Health') {
                    // if this point is reached, logs should be archived
                    ARCHIVE_LOGS_FLAG = true
                    stackName = 'osm'
                    sshCommand remote: remote, command: """
                        /usr/share/osm-devops/installers/osm_health.sh -k -s ${stackName}
                    """
                } // stage("OSM Health")
            } // if ( params.DO_INSTALL )


///////////////////////////////////////////////////////////////////////////////////////
// Execute Robot tests
///////////////////////////////////////////////////////////////////////////////////////
            stage_archive = false
            if ( params.DO_ROBOT ) {
                try {
                    stage('System Integration Test') {
                        if (useCharmedInstaller) {
                            tempdir = sh(returnStdout: true, script: 'mktemp -d').trim()
                            sh(script: "touch ${tempdir}/hosts")
                            hostfile = "${tempdir}/hosts"
                            sh """cat << EOF > ${hostfile}
127.0.0.1           localhost
${remote.host}      prometheus.${remote.host}.nip.io nbi.${remote.host}.nip.io
EOF"""
                        } else {
                            hostfile = null
                        }

                        jujuPassword = sshCommand remote: remote, command: '''
                            echo `juju gui 2>&1 | grep password | cut -d: -f2`
                        '''

                        run_robot_systest(
                            containerName,
                            params.ROBOT_TAG_NAME,
                            osmHostname,
                            prometheusHostname,
                            prometheusPort,
                            OCI_REGISTRY_URL,
                            params.ROBOT_VIM,
                            params.ROBOT_PORT_MAPPING_VIM,
                            params.KUBECONFIG,
                            params.CLOUDS,
                            hostfile,
                            jujuPassword,
                            SSH_KEY,
                            params.ROBOT_PASS_THRESHOLD,
                            params.ROBOT_UNSTABLE_THRESHOLD
                        )
                    } // stage("System Integration Test")
                } finally {
                    stage('After System Integration test') {
                        if (currentBuild.result != 'FAILURE') {
                            stage_archive = keep_artifacts
                        } else {
                            println('Systest test failed, throwing error')
                            error = new Exception('Systest test failed')
                            currentBuild.result = 'FAILURE'
                            throw error
                        }
                    }
                }
            } // if ( params.DO_ROBOT )

            if (params.SAVE_ARTIFACTS_OVERRIDE || stage_archive) {
                stage('Archive') {
                    // Archive the tested repo
                    dir("${RELEASE_DIR}") {
                        ci_helper.archive(params.ARTIFACTORY_SERVER, RELEASE, GERRIT_BRANCH, 'tested')
                    }
                    if (params.DO_DOCKERPUSH) {
                        stage('Publish to Dockerhub') {
                            parallelSteps = [:]
                            for (buildStep in containerList) {
                                def module = buildStep
                                def moduleName = buildStep.toLowerCase()
                                def dockerTag = params.DOCKER_TAG
                                def moduleTag = containerName

                                parallelSteps[module] = {
                                    dir("$module") {
                                        sh("docker pull ${INTERNAL_DOCKER_REGISTRY}opensourcemano/${moduleName}:${moduleTag}")
                                        sh("""docker tag ${INTERNAL_DOCKER_REGISTRY}opensourcemano/${moduleName}:${moduleTag} \
                                           opensourcemano/${moduleName}:${dockerTag}""")
                                        sh "docker push opensourcemano/${moduleName}:${dockerTag}"
                                    }
                                }
                            }
                            parallel parallelSteps
                        }
                    } // if (params.DO_DOCKERPUSH)
                } // stage('Archive')
            } // if (params.SAVE_ARTIFACTS_OVERRIDE || stage_archive)
        } // dir(OSM_DEVOPS)
    } finally {
        // stage('Debug') {
        //     sleep 900
        // }
        stage('Archive Container Logs') {
            if ( ARCHIVE_LOGS_FLAG ) {
                try {
                    // Archive logs
                    remote = [
                        name: containerName,
                        host: IP_ADDRESS,
                        user: 'ubuntu',
                        identityFile: SSH_KEY,
                        allowAnyHosts: true,
                        logLevel: 'INFO',
                        pty: true
                    ]
                    println('Archiving container logs')
                    archive_logs(remote)
                } catch (Exception e) {
                    println('Error fetching logs: '+ e.getMessage())
                }
            } // end if ( ARCHIVE_LOGS_FLAG )
        }
        stage('Cleanup') {
            if ( params.DO_INSTALL && server_id != null) {
                delete_vm = true
                if (error && params.SAVE_CONTAINER_ON_FAIL ) {
                    delete_vm = false
                }
                if (!error && params.SAVE_CONTAINER_ON_PASS ) {
                    delete_vm = false
                }

                if ( delete_vm ) {
                    if (server_id != null) {
                        println("Deleting VM: $server_id")
                        sh """#!/bin/sh -e
                            for line in `grep OS ~/hive/robot-systest.cfg | grep -v OS_CLOUD` ; do export \$line ; done
                            openstack server delete ${server_id}
                        """
                    } else {
                        println("Saved VM $server_id in ETSI VIM")
                    }
                }
            }
            if ( http_server_name != null ) {
                sh "docker stop ${http_server_name} || true"
                sh "docker rm ${http_server_name} || true"
            }

            if ( devopstempdir != null ) {
                sh "rm -rf ${devopstempdir}"
            }
        }
    }
}
