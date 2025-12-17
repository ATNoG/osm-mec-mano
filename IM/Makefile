# Copyright 2017 Sandvine
# Copyright 2017-2018 Telefonica
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

# NOTE: pyang and pyangbind are required for build

.PHONY: all clean package trees yang-ietf openapi_schemas yang2swagger
JAVA := /usr/lib/jvm/java-21-openjdk-amd64/bin/java
PYANG := pyang
ifeq ($(OS),Windows_NT)     # is Windows_NT on XP, 2000, 7, Vista, 10...
    PYTHON_INTERPRETER := python
else
    PYTHON_INTERPRETER := python3
endif
PYBINDPLUGIN := $(shell $(PYTHON_INTERPRETER) -c \
    'import pyangbind; import os; print(os.path.join(f"{os.path.dirname(pyangbind.__file__)}", "plugin"))')

YANG_DESC_MODELS := vnfd nsd nst nsi etsi-nfv-vnfd etsi-nfv-nsd
YANG_RECORD_MODELS := vnfr nsr
PYTHON_MODELS := $(addsuffix .py, $(YANG_DESC_MODELS))
YANG_DESC_TREES := $(addsuffix .tree.txt, $(YANG_DESC_MODELS))
YANG_DESC_JSTREES := $(addsuffix .html, $(YANG_DESC_MODELS))
YANG_RECORD_TREES := $(addsuffix .rec.tree.txt, $(YANG_RECORD_MODELS))
YANG_RECORD_JSTREES := $(addsuffix .rec.html, $(YANG_RECORD_MODELS))
OPENAPI_SCHEMAS := osm.yaml

OUT_DIR := osm_im
TREES_DIR := osm_im_trees
MODEL_DIR := models/yang
SOL006_MODEL_DIR := sol006_model/src/yang
SOL006_AUGMENTS_DIR := models/augments/*

Q?=@

PYANG_OPTIONS := -Werror

all: models trees openapi_schemas
	$(MAKE) package

models: sol006_deps $(PYTHON_MODELS) rename_etsi_nfv_py

trees: $(YANG_DESC_TREES) $(YANG_DESC_JSTREES)

openapi_schemas: $(OPENAPI_SCHEMAS)

$(TREES_DIR):
	$(Q)mkdir -p $(TREES_DIR)

%.py: yang-ietf
	$(Q)echo generating $@ from $*.yang
	$(if $(findstring etsi,$@), $(eval DIR=$(SOL006_MODEL_DIR)),$(eval DIR=$(MODEL_DIR)))
	$(if $(findstring etsi,$@), $(eval AUGMENTS_DIR=$(SOL006_AUGMENTS_DIR)),$(eval AUGMENTS_DIR=))
	$(Q)pyang $(PYANG_OPTIONS) --path $(DIR) --plugindir "$(PYBINDPLUGIN)" -f pybind -o $(OUT_DIR)/$@ $(AUGMENTS_DIR) $(DIR)/$*.yang

%.tree.txt: $(TREES_DIR) yang-ietf
	$(Q)echo generating $@ from $*.yang
	$(if $(findstring etsi,$@), $(eval DIR=$(SOL006_MODEL_DIR)),$(eval DIR = $(MODEL_DIR)))
	$(if $(findstring etsi,$@), $(eval AUGMENTS_DIR=$(SOL006_AUGMENTS_DIR)),$(eval AUGMENTS_DIR=))
	$(Q)pyang $(PYANG_OPTIONS) --path $(DIR) -f tree -o $(TREES_DIR)/$@ $(DIR)/$*.yang $(AUGMENTS_DIR)

%.html: $(TREES_DIR) yang-ietf
	$(Q)echo generating $@ from $*.yang
	$(if $(findstring etsi,$@), $(eval DIR=$(SOL006_MODEL_DIR)),$(eval DIR = $(MODEL_DIR)))
	$(if $(findstring etsi,$@), $(eval AUGMENTS_DIR=$(SOL006_AUGMENTS_DIR)),$(eval AUGMENTS_DIR=))
	$(Q)pyang $(PYANG_OPTIONS) --path $(DIR) -f jstree -o $(TREES_DIR)/$@ $(DIR)/$*.yang $(AUGMENTS_DIR)
	$(Q)sed -r -i 's|data\:image/gif\;base64,R0lGODlhS.*RCAA7|https://osm.etsi.org/images/OSM-logo.png\" width=\"175\" height=\"60|g' $(TREES_DIR)/$@
	$(Q)sed -r -i 's|<a href=\"http://www.tail-f.com">|<a href="http://osm.etsi.org">|g' $(TREES_DIR)/$@

%.rec.tree.txt: $(TREES_DIR) yang-ietf
	$(Q)echo generating $@ from $*.yang
	$(if $(findstring etsi,$@), $(eval DIR=$(SOL006_MODEL_DIR)),$(eval DIR=$(MODEL_DIR)))
	$(Q)pyang $(PYANG_OPTIONS) --path $(DIR) -f tree -o $(TREES_DIR)/$@ $(DIR)/$*.yang
	$(Q)mv $(TREES_DIR)/$@ $(TREES_DIR)/$*.tree.txt

%.rec.html: $(TREES_DIR) yang-ietf
	$(Q)echo generating $@ from $*.yang
	$(if $(findstring etsi,$@), $(eval DIR=$(SOL006_MODEL_DIR)),$(eval DIR=$(MODEL_DIR)))
	$(Q)pyang $(PYANG_OPTIONS) --path $(DIR) -f jstree -o $(TREES_DIR)/$@ $(DIR)/osm-project.yang $(DIR)/$*.yang
	$(Q)sed -r -i 's|data\:image/gif\;base64,R0lGODlhS.*RCAA7|https://osm.etsi.org/images/OSM-logo.png\" width=\"175\" height=\"60|g' $(TREES_DIR)/$@
	$(Q)sed -r -i 's|<a href=\"http://www.tail-f.com">|<a href="http://osm.etsi.org">|g' $(TREES_DIR)/$@
	$(Q)mv $(TREES_DIR)/$@ $(TREES_DIR)/$*.html

osm.yaml: yang-ietf yang2swagger
	$(Q)echo generating $@
	$(Q)$(JAVA) -jar ${HOME}/.m2/repository/com/mrv/yangtools/swagger-generator-cli/2.1.0/swagger-generator-cli-2.1.0-executable.jar -yang-dir $(MODEL_DIR) -output $(OUT_DIR)/$@

yang-ietf:
	$(Q)wget -q https://raw.githubusercontent.com/YangModels/yang/master/standard/ietf/RFC/ietf-yang-types%402013-07-15.yang -O $(MODEL_DIR)/ietf-yang-types.yang
	$(Q)wget -q https://raw.githubusercontent.com/YangModels/yang/master/standard/ietf/RFC/ietf-inet-types%402013-07-15.yang -O $(MODEL_DIR)/ietf-inet-types.yang
	$(Q)cp $(MODEL_DIR)/ietf-yang-types.yang $(SOL006_MODEL_DIR)/ietf-yang-types.yang
	$(Q)cp $(MODEL_DIR)/ietf-inet-types.yang $(SOL006_MODEL_DIR)/ietf-inet-types.yang

yang2swagger:
	$(Q)mkdir -p ${HOME}/.m2
	$(Q)wget -q -O ${HOME}/.m2/settings.xml https://raw.githubusercontent.com/opendaylight/odlparent/master/settings.xml
	$(Q)git clone https://github.com/bartoszm/yang2swagger.git
	$(Q)git -C yang2swagger checkout tags/2.1.0
	$(Q)mvn -f yang2swagger/pom.xml clean install

package:
	./build-docs.sh

sol006_deps:
	$(Q)git clone --single-branch --branch v2.6.1 https://forge.etsi.org/rep/nfv/SOL006.git sol006_model
	$(Q)patch -p2 < patch/deref_warnings.patch
	$(Q)patch -p2 < patch/nested_workaround.patch

rename_etsi_nfv_py:
	mv osm_im/etsi-nfv-nsd.py osm_im/etsi_nfv_nsd.py
	mv osm_im/etsi-nfv-vnfd.py osm_im/etsi_nfv_vnfd.py

clean:
	$(Q)rm -rf dist sol006_model osm_im.egg-info deb deb_dist *.gz osm-imdocs* yang2swagger $(TREES_DIR)
	$(Q)rm -rf debian/osm-imdocs.install
	$(Q)rm -rf osm_im/etsi_nfv_nsd.py osm_im/etsi_nfv_vnfd.py
	$(Q)rm -rf osm_im/nsd.py osm_im/nsi.py osm_im/nst.py osm_im/osm.yaml osm_im/vnfd.py
