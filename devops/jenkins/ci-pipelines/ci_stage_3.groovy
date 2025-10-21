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
        string(defaultValue: '/home/jenkins/hive/etsi-vim-prometheus.json',
               description: 'Prometheus configuration file in ETSI VIM',
               name: 'PROMETHEUS_CONFIG_VIM'),
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
// Helper Classes & Functions
////////////////////////////////////////////////////////////////////////////////////////
/** Usage:
 *   def dr = new DockerRunner(this)
 *   stdout = dr.run(
 *       image   : "opensourcemano/tests:${tag}",
 *       entry   : "/usr/bin/osm",        // optional
 *       envVars : [ "OSM_HOSTNAME=${host}" ],
 *       envFile : myEnv,
 *       mounts  : [
 *                  "${clouds}:/etc/openstack/clouds.yaml",
 *                  "${kubeconfig}:/root/.kube/config"
 *                ],
 *       cmd     : "vim-create --name osm …"
 *   )
 */
class DockerRunner implements Serializable {
    def steps                       // Jenkins DSL context (`this` from the script)
    DockerRunner(def steps) { this.steps = steps }

    /** Returns stdout (trimmed) if returnStdout is true; throws Exception on non-zero exit */
    String run(Map args = [:]) {
        def returnStdout = args.remove('returnStdout') ?: false
        def envFile  = args.envFile ?: ''
        def entry    = args.entry   ? "--entrypoint ${args.entry}" : ''
        def mounts   = (args.mounts ?: [])
                        .findAll { it && it.trim() }  // Filter out null/empty values
                        .collect { "-v ${it}" }.join(' ')
        def envs      = (args.envVars ?: [])
                        .findAll { it && it.trim() }  // Filter out null/empty values
                        .collect { "--env ${it}" }.join(' ')
        def image    = args.image ?: ''
        def cmd      = args.cmd   ?: ''
        def fullCmd  = """docker run ${entry} ${envs} ${envFile ? "--env-file ${envFile}" : ''} ${mounts} ${image} ${cmd}"""

        def result = null
        try {
            if (returnStdout) {
                result = steps.sh(returnStdout: true, script: fullCmd).trim()
            } else {
                steps.sh(script: fullCmd)
            }
        } catch (Exception ex) {
            throw new Exception("docker run failed → ${ex.message}")
        } finally {
            steps.echo("Command executed: ${fullCmd}")
        }
        return result
    }
}

/* -------------------------------------------------------------------
 *  create_vcluster  – spin up a vcluster in the target OSM cluster
 * @params:
 *  tagName - The OSM test docker image tag to use
 *  kubeconfigPath - The path of the OSM kubernetes master configuration
 *                   file
 ** Usage:
 *    create_vcluster(containerName, env.OSM_KUBECONFIG_PATH)
 * ------------------------------------------------------------------- */
void create_vcluster(String tagName, String kubeconfigPath) {
    def dr     = new DockerRunner(this)
    def mounts = ["${kubeconfigPath}:/root/.kube/config"]
    def envs   = ["KUBECONFIG=/root/.kube/config"]
    def image  = "opensourcemano/tests:${tagName}"

    // 1) create vcluster namespace
    dr.run(
        image   : image,
        entry   : "kubectl",
        envVars : envs,
        mounts  : mounts,
        cmd     : "create namespace vcluster || true"
    )
    println("Namespace 'vcluster' ensured")

    // 2) create vcluster
    dr.run(
        image   : image,
        entry   : "vcluster",
        envVars : envs,
        mounts  : mounts,
        cmd     : "create e2e -n vcluster --connect=false -f /etc/vcluster.yaml"
    )
    println("vcluster 'e2e' created")

    // 3) poll until Status is Running
    int maxWaitMinutes = 2
    long deadline = System.currentTimeMillis() + (maxWaitMinutes * 60 * 1000)
    boolean running = false
    String lastOut = ''

    while (System.currentTimeMillis() < deadline) {
        try {
            lastOut = dr.run(
                returnStdout: true,
                image   : image,
                entry   : "/bin/sh",
                envVars : envs,
                mounts  : mounts,
                cmd     : '''-c "vcluster list --output json | jq -r \'.[] | select(.Name==\\\"e2e\\\") | .Status\'"'''
            ).trim()
        } catch (Exception e) {
            println("Polling command failed: ${e.message}. Will retry.")
            lastOut = "Error: ${e.message}"
        }

        println("Polling for vcluster status. Current status: '${lastOut}'")

        if (lastOut == 'Running') {
            running = true
            break // Exit the while loop
        }

        sleep 10 // Wait 10 seconds before the next poll
    }

    if (!running) {
        println("vcluster status after timeout: ${lastOut}")
        throw new Exception("vcluster 'e2e' did not reach 'Running' state within ${maxWaitMinutes} minutes.")
    }

    // 4) get vcluster kubeconfig
    env.VCLUSTER_KUBECONFIG_PATH = "${WORKSPACE}/kubeconfig/vcluster_config"
    dr.run(
        image   : image,
        entry   : "vcluster",
        envVars : envs,
        mounts  : mounts,
        cmd     : "connect e2e -n vcluster --server e2e.vcluster.svc.cluster.local:443 --print > ${env.VCLUSTER_KUBECONFIG_PATH}"
    )

    println("vcluster 'e2e' is Running ✔")
}

void register_etsi_vim_account(
    String tagName,
    String osmHostname,
    String envfile=null,
    String portmappingfile=null,
    String kubeconfig=null,
    String clouds=null,
    String prometheusconfigfile=null
) {
    String VIM_TARGET = "osm"
    String VIM_MGMT_NET = "osm-ext"
    String OS_PROJECT_NAME = "osm_jenkins"
    String OS_AUTH_URL = "http://172.21.247.1:5000/v3"
    String entrypointCmd = "/usr/bin/osm"
    tempdir = sh(returnStdout: true, script: 'mktemp -d').trim()
    String environmentFile = ''
    if (envfile) {
        environmentFile = envfile
    } else {
        sh(script: "touch ${tempdir}/env")
        environmentFile = "${tempdir}/env"
    }
    int attempts = 3
    def dr = new DockerRunner(this)
    while (attempts >= 0) {
        try {
            println("Attempting to register VIM account (remaining attempts: ${attempts})")
            withCredentials([usernamePassword(credentialsId: 'openstack-jenkins-credentials',
                        passwordVariable: 'OS_PASSWORD', usernameVariable: 'OS_USERNAME')]) {
                String entrypointArgs = """vim-create --name ${VIM_TARGET} --user ${OS_USERNAME} \
                        --password ${OS_PASSWORD} --tenant ${OS_PROJECT_NAME} \
                        --auth_url ${OS_AUTH_URL} --account_type openstack --description vim \
                        --prometheus_config_file /root/etsi-vim-prometheus.json \
                        --config '{management_network_name: ${VIM_MGMT_NET}, dataplane_physical_net: physnet2}' || true"""
                String createOutput = dr.run(
                    image   : "opensourcemano/tests:${tagName}",
                    entry   : entrypointCmd,
                    envVars : [ "OSM_HOSTNAME=${osmHostname}" ],
                    envFile : environmentFile,
                    mounts  : [
                        "${clouds}:/etc/openstack/clouds.yaml",
                        "${kubeconfig}:/root/.kube/config",
                        "${portmappingfile}:/root/port-mapping.yaml",
                        "${prometheusconfigfile}:/root/etsi-vim-prometheus.json"
                    ],
                    cmd     : entrypointArgs,
                    returnStdout: true
                )
                println("VIM Creation Output: ${createOutput}")
            }

            // Check if the VIM is ENABLED
            int statusChecks = 5
            while (statusChecks > 0) {
                sleep(10)  // Wait for 10 seconds before checking status
                entrypointArgs = """vim-list --long | grep ${VIM_TARGET}"""
                String vimList = dr.run(
                    image   : "opensourcemano/tests:${tagName}",
                    entry   : entrypointCmd,
                    envVars : [ "OSM_HOSTNAME=${osmHostname}" ],
                    envFile : environmentFile,
                    mounts  : [
                        "${clouds}:/etc/openstack/clouds.yaml",
                        "${kubeconfig}:/root/.kube/config",
                        "${portmappingfile}:/root/port-mapping.yaml",
                        "${prometheusconfigfile}:/root/etsi-vim-prometheus.json"
                    ],
                    cmd     : entrypointArgs,
                    returnStdout: true
                )
                println("VIM List output: ${vimList}")
                if (vimList.contains("ENABLED")) {
                    println("VIM successfully registered and is ENABLED.")
                    return
                }
                statusChecks--
            }

            // If stuck, delete and retry
            println("VIM stuck for more than 50 seconds, deleting and retrying...")
            entrypointArgs = """vim-delete --force ${VIM_TARGET}"""
            String deleteOutput = dr.run(
                image   : "opensourcemano/tests:${tagName}",
                entry   : entrypointCmd,
                envVars : [ "OSM_HOSTNAME=${osmHostname}" ],
                envFile : environmentFile,
                mounts  : [
                    "${clouds}:/etc/openstack/clouds.yaml",
                    "${kubeconfig}:/root/.kube/config",
                    "${portmappingfile}:/root/port-mapping.yaml",
                    "${prometheusconfigfile}:/root/etsi-vim-prometheus.json"
                ],
                cmd     : entrypointArgs,
                returnStdout: true
            )
            println("VIM Deletion Output: ${deleteOutput}")
            sleep(5)
        } catch (Exception e) {
            println("Something happened during the execution of docker run: ${e.message}")
        }
        attempts--
    }
    // If all attempts fail, throw an error
    println("VIM failed to enter ENABLED state after multiple attempts.")
    throw new Exception("VIM registration failed after multiple retries.")
}

void register_etsi_k8s_cluster(
    String tagName,
    String osmHostname,
    String envfile=null,
    String portmappingfile=null,
    String kubeconfig=null,
    String clouds=null,
    String prometheusconfigfile=null
) {
    String K8S_CLUSTER_TARGET = "osm"
    String VIM_TARGET = "osm"
    String VIM_MGMT_NET = "osm-ext"
    String K8S_CREDENTIALS = "/root/.kube/config"
    String entrypointCmd = "/usr/bin/osm"
    tempdir = sh(returnStdout: true, script: 'mktemp -d').trim()
    String environmentFile = ''
    if (envfile) {
        environmentFile = envfile
    } else {
        sh(script: "touch ${tempdir}/env")
        environmentFile = "${tempdir}/env"
    }
    int attempts = 3
    def dr = new DockerRunner(this)
    while (attempts >= 0) {
        try {
            println("Attempting to register K8s cluster (remaining attempts: ${attempts})")
            String entrypointArgs = """k8scluster-add ${K8S_CLUSTER_TARGET} --creds ${K8S_CREDENTIALS} --version "v1" \
                        --description "Robot-cluster" --skip-jujubundle --vim ${VIM_TARGET} \
                        --k8s-nets '{net1: ${VIM_MGMT_NET}}'"""
            String createOutput = dr.run(
                image   : "opensourcemano/tests:${tagName}",
                entry   : entrypointCmd,
                envVars : [ "OSM_HOSTNAME=${osmHostname}" ],
                envFile : environmentFile,
                mounts  : [
                    "${clouds}:/etc/openstack/clouds.yaml",
                    "${kubeconfig}:/root/.kube/config",
                    "${portmappingfile}:/root/port-mapping.yaml",
                    "${prometheusconfigfile}:/root/etsi-vim-prometheus.json"
                ],
                cmd     : entrypointArgs,
                returnStdout: true
            )
            println("K8s Cluster Addition Output: ${createOutput}")

            // Check if the K8s cluster is ENABLED
            int statusChecks = 10
            while (statusChecks > 0) {
                sleep(10)  // Wait for 10 seconds before checking status
                entrypointArgs = """k8scluster-list | grep ${K8S_CLUSTER_TARGET}"""
                String clusterList = dr.run(
                    image   : "opensourcemano/tests:${tagName}",
                    entry   : entrypointCmd,
                    envVars : [ "OSM_HOSTNAME=${osmHostname}" ],
                    envFile : environmentFile,
                    mounts  : [
                        "${clouds}:/etc/openstack/clouds.yaml",
                        "${kubeconfig}:/root/.kube/config",
                        "${portmappingfile}:/root/port-mapping.yaml",
                        "${prometheusconfigfile}:/root/etsi-vim-prometheus.json"
                    ],
                    cmd     : entrypointArgs,
                    returnStdout: true
                )
                println("K8s Cluster List Output: ${clusterList}")
                if (clusterList.contains("ENABLED")) {
                    println("K8s cluster successfully registered and is ENABLED.")
                    return
                }
                statusChecks--
            }

            // If stuck, delete and retry
            println("K8s cluster stuck for more than 50 seconds, deleting and retrying...")
            entrypointArgs = """k8scluster-show ${K8S_CLUSTER_TARGET}"""
            String showOutput = dr.run(
                image   : "opensourcemano/tests:${tagName}",
                entry   : entrypointCmd,
                envVars : [ "OSM_HOSTNAME=${osmHostname}" ],
                envFile : environmentFile,
                mounts  : [
                    "${clouds}:/etc/openstack/clouds.yaml",
                    "${kubeconfig}:/root/.kube/config",
                    "${portmappingfile}:/root/port-mapping.yaml",
                    "${prometheusconfigfile}:/root/etsi-vim-prometheus.json"
                ],
                cmd     : entrypointArgs,
                returnStdout: true
            )
            println("K8s Cluster Show Output: ${showOutput}")
            entrypointArgs = """k8scluster-delete ${K8S_CLUSTER_TARGET}"""
            String deleteOutput = dr.run(
                image   : "opensourcemano/tests:${tagName}",
                entry   : entrypointCmd,
                envVars : [ "OSM_HOSTNAME=${osmHostname}" ],
                envFile : environmentFile,
                mounts  : [
                    "${clouds}:/etc/openstack/clouds.yaml",
                    "${kubeconfig}:/root/.kube/config",
                    "${portmappingfile}:/root/port-mapping.yaml",
                    "${prometheusconfigfile}:/root/etsi-vim-prometheus.json"
                ],
                cmd     : entrypointArgs,
                returnStdout: true
            )
            println("K8s Cluster Deletion Output: ${deleteOutput}")
            sleep(5)
        } catch (Exception e) {
            println("Something happened during the execution of docker run: ${e.message}")
        }
        attempts--
    }
    // If all attempts fail, throw an error
    println("K8s cluster failed to enter ENABLED state after multiple attempts.")
    throw new Exception("K8s cluster registration failed after multiple retries.")
}

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
                       String unstableThreshold='0.0',
                       Map extraEnvVars=null,
                       Map extraVolMounts=null) {
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
        PROMETHEUS_PORT_VAR = "PROMETHEUS_PORT=${prometheusPort}"
    }
    hostfilemount = ''
    if (hostfile) {
        hostfilemount = "${hostfile}:/etc/hosts"
    }

    JUJU_PASSWORD_VAR = ''
    if (jujuPassword != null) {
        JUJU_PASSWORD_VAR = "JUJU_PASSWORD=${jujuPassword}"
    }

    try {
        withCredentials([usernamePassword(credentialsId: 'gitlab-oci-test',
                        passwordVariable: 'OCI_REGISTRY_PSW', usernameVariable: 'OCI_REGISTRY_USR')]) {

            def baseEnvVars = [
                "OSM_HOSTNAME=${osmHostname}",
                "PROMETHEUS_HOSTNAME=${prometheusHostname}",
                PROMETHEUS_PORT_VAR ? "${PROMETHEUS_PORT_VAR}" : null,
                JUJU_PASSWORD_VAR ? "${JUJU_PASSWORD_VAR}" : null,
                "OCI_REGISTRY_URL=${ociRegistryUrl}",
                "OCI_REGISTRY_USER=${OCI_REGISTRY_USR}",
                "OCI_REGISTRY_PASSWORD=${OCI_REGISTRY_PSW}"
            ].findAll { it != null }
            def baseMounts = [
                "${clouds}:/etc/openstack/clouds.yaml",
                "${osmRSAfile}:/root/osm_id_rsa",
                "${kubeconfig}:/root/.kube/config",
                "${tempdir}:/robot-systest/reports",
                "${portmappingfile}:/root/port-mapping.yaml",
                "${hostfilemount}"
            ].findAll { it != null }

            // Convert and merge extra parameters
            def extraEnvVarsList = extraEnvVars?.collect { key, value -> "${key}=${value}" } ?: []
            def extraVolMountsList = extraVolMounts?.collect { hostPath, containerPath -> "${hostPath}:${containerPath}" } ?: []

            def dr = new DockerRunner(this)
            dr.run(
                image   : "opensourcemano/tests:${tagName}",
                envVars : baseEnvVars + extraEnvVarsList,
                envFile : "${environmentFile}",
                mounts  : baseMounts + extraVolMountsList,
                cmd     : "-t ${testName}"
            )
        }
    } catch (Exception e) {
        println("Robotest execution failed with: ${e.message}")
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

    sshCommand remote: remote, command: '''mkdir -p logs/dags logs/vcluster logs/flux-system logs/events logs/system'''
    // Collect Kubernetes events
    sshCommand remote: remote, command: '''
        echo "Extracting Kubernetes events"
        kubectl get events --all-namespaces --sort-by='.lastTimestamp' -o wide > logs/events/k8s-events.log 2>&1 || true
        kubectl get events -n osm --sort-by='.lastTimestamp' -o wide > logs/events/osm-events.log 2>&1 || true
        kubectl get events -n vcluster --sort-by='.lastTimestamp' -o wide > logs/events/vcluster-events.log 2>&1 || true
        kubectl get events -n flux-system --sort-by='.lastTimestamp' -o wide > logs/events/flux-system-events.log 2>&1 || true
    '''
    // Collect host logs
    sshCommand remote: remote, command: '''
      echo "Collect system logs"
      if command -v journalctl >/dev/null; then
        journalctl > logs/system/system.log
      fi

      for entry in syslog messages; do
        [ -e "/var/log/${entry}" ] && cp -f /var/log/${entry} logs/system/"${entry}.log"
      done

      echo "Collect active services"
      case "$(cat /proc/1/comm)" in
        systemd)
          systemctl list-units > logs/system/services.txt 2>&1
          ;;
        *)
          service --status-all >> logs/system/services.txt 2>&1
          ;;
      esac

      top -b -n 1 > logs/system/top.txt 2>&1
      ps fauxwww > logs/system/ps.txt 2>&1
    '''


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
                > logs/$deployment.log || true
            done
        '''
        sshCommand remote: remote, command: '''
            for statefulset in `kubectl -n osm get statefulsets | grep -v operator | grep -v NAME| awk '{print $1}'`; do
                echo "Extracting log for $statefulset"
                kubectl -n osm logs statefulsets/$statefulset --timestamps=true --all-containers 2>&1 \
                > logs/$statefulset.log || true
            done
        '''
        sshCommand remote: remote, command: '''
            schedulerPod="$(kubectl get pods -n osm | grep osm-scheduler| awk '{print $1; exit}')"; \
            echo "Extracting logs from Airflow DAGs from pod ${schedulerPod}"; \
            kubectl -n osm cp ${schedulerPod}:/opt/airflow/logs/scheduler/latest/dags logs/dags -c scheduler 2>&1 || true
        '''
        // Collect vcluster namespace logs
        sshCommand remote: remote, command: '''
            echo "Extracting logs from vcluster namespace"
            for pod in `kubectl get pods -n vcluster | grep -v NAME | awk '{print $1}'`; do
                echo "Extracting log for vcluster pod: $pod"
                kubectl logs -n vcluster $pod --timestamps=true --all-containers 2>&1 \
                > logs/vcluster/$pod.log || true
            done
        '''
        // Collect flux-system namespace logs
        sshCommand remote: remote, command: '''
            echo "Extracting logs from flux-system namespace"
            for pod in `kubectl get pods -n flux-system | grep -v NAME | awk '{print $1}'`; do
                echo "Extracting log for flux-system pod: $pod"
                kubectl logs -n flux-system $pod --timestamps=true --all-containers 2>&1 \
                > logs/flux-system/$pod.log || true
            done
        '''
    }

    sh 'rm -rf logs'
    sshCommand remote: remote, command: '''ls -al logs logs/vcluster logs/events logs/flux-system logs/system'''
    sshGet remote: remote, from: 'logs', into: '.', override: true
    archiveArtifacts artifacts: 'logs/*.log, logs/dags/*.log, logs/vcluster/*.log, logs/events/*.log, logs/flux-system/*.log, logs/system/**'
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
                    list = ['RO', 'osmclient', 'IM', 'devops', 'MON', 'NBI',
                            'common', 'LCM', 'NG-UI', 'NG-SA', 'tests']
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
                        wget https://osm-download.etsi.org/ftp/osm-18.0-eighteen/install_osm.sh
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
                    sshCommand remote: remote, command: """
                        OSM_HOSTNAME=nbi.${remote.host}.nip.io ~/.local/bin/osm vim-list
                    """
                } // stage("OSM Health")
///////////////////////////////////////////////////////////////////////////////////////
// Get OSM Kubeconfig and store it for future usage
///////////////////////////////////////////////////////////////////////////////////////
                stage('OSM Get kubeconfig') {
                  // Delete always kubecofig directory to ensure it is clean.
                  sh '''
                    rm -rf "${WORKSPACE}/kubeconfig"
                    mkdir -p "${WORKSPACE}/kubeconfig"
                  '''
                  env.OSM_KUBECONFIG_PATH = "${WORKSPACE}/kubeconfig/osm_config"
                  sshGet  remote: remote,
                          from:  "/home/ubuntu/.kube/config",
                          into:  env.OSM_KUBECONFIG_PATH,
                          override: true
                  sh "cat ${env.OSM_KUBECONFIG_PATH}"
                } // stage('OSM Get kubeconfig')

///////////////////////////////////////////////////////////////////////////////////////
// Create vCluster for GitOps test execution
///////////////////////////////////////////////////////////////////////////////////////
                stage('Create vCluster') {
                  // create an isolated vcluster for the E2E tests
                  create_vcluster(containerName, env.OSM_KUBECONFIG_PATH)
                  // Verify vCluster kubeconfig is available
                  sh "cat ${env.VCLUSTER_KUBECONFIG_PATH}"
                } // stage('Create vCluster')
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

                        register_etsi_vim_account(
                            containerName,
                            osmHostname,
                            params.ROBOT_VIM,
                            params.ROBOT_PORT_MAPPING_VIM,
                            params.KUBECONFIG,
                            params.CLOUDS,
                            params.PROMETHEUS_CONFIG_VIM
                        )
                        register_etsi_k8s_cluster(
                            containerName,
                            osmHostname,
                            params.ROBOT_VIM,
                            params.ROBOT_PORT_MAPPING_VIM,
                            params.KUBECONFIG,
                            params.CLOUDS,
                            params.PROMETHEUS_CONFIG_VIM
                        )
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
                            params.ROBOT_UNSTABLE_THRESHOLD,
                            // extraEnvVars map of extra environment variables
                            ['CLUSTER_KUBECONFIG_CREDENTIALS': '/robot-systest/cluster-kubeconfig.yaml'],
                            // extraVolMounts map of extra volume mounts
                            [(env.VCLUSTER_KUBECONFIG_PATH): '/robot-systest/cluster-kubeconfig.yaml']
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
