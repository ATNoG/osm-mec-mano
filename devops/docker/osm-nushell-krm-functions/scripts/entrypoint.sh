#!/bin/sh
#######################################################################################
# Copyright ETSI Contributors and Others.
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
#######################################################################################


# If the main command is "nu", it should run as if it where a basic "nu" container, but with the expected environment variables and libraries.
# Otherwise, it must be an OSM model operation, so it should be fed by the appropriate instance model in a pipeline

# Check if the first argument is "nu"
if [ "$1" = "nu" ]; then
  # If it is just "nu", with no extra arguments, just runs it with the right environment
  if [ "$#" -eq 1 ]; then
    exec nu --env-config scripts/entrypoint-config.nu
  # Otherwise, adds the rest of arguments after the environment is loaded
  else
    # Shift the first argument ("nu") off, leaving only the remaining arguments
    shift

    # Construct the final command with the joined arguments
    exec nu --env-config scripts/entrypoint-config.nu "$@"
  fi
else
  # Otherwise, launches the command with special configuration and feeding it by the instance model in a pipeline
  NU_COMMAND="\$model_instance | $@"
  exec nu --env-config scripts/entrypoint-config.nu -c "${NU_COMMAND}"
fi
