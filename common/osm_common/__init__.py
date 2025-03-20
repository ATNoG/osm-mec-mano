# -*- coding: utf-8 -*-

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
import logging

version = "7.0.0.post4"
date_version = "2019-01-21"

# try to get version from installed package. Skip if fails
try:
    from pkg_resources import get_distribution

    version = get_distribution("osm_common").version

except Exception as init_error:
    logging.exception(f"{init_error} occured while getting the common version")
