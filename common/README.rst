# Copyright 2018 Telefonica S.A.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.

===========
osm-common
===========
Contains common modules for OSM lightweight build, that manages database, storage and messaging access.
It uses a plugin stile in order to easy migration to other technologies, as e.g. different database or storage object system.
For database: mongo and memory (volatile) are implemented.
For messaging: Kafka and local file system are implemented.
For storage: local file system is implemented.

