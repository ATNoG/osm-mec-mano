
cd k3s-through-ansible
osm nspkg-delete k3s_through_ansible_nsd
osm nfpkg-delete k3s_through_ansible_vnfd
osm nfpkg-create k3s_through_ansible_vnf/
osm nspkg-create k3s_through_ansible_ns/
cd ..


cd k3s-through-ansible
osm ns-create --ns_name dev_k3s_ns --nsd_name k3s_through_ansible_nsd --vim_account openstack --config_file vars.yaml
cd ..


osm ns-action dev_k3s_ns --vnf_name k3s_through_ansible_vnf --vdu_id worker --vdu_count 0 --action_name worker --params '{controller_host: "vm_ip", token: "tokenReplace"}'
osm ns-action dev_k3s_ns --vnf_name k3s_through_ansible_vnf --vdu_id worker --vdu_count 1 --action_name worker --params '{controller_host: "vm_ip", token: "tokenReplace"}'


osm ns-delete dev_k3s_ns
osm vim-delete dummy-teste
osm k8scluster-delete teste




cd OSM-dev
./dev_lcm.sh apply build
cd ..



cd OSM-dev
./dev_lcm.sh undo
cd ..


