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

# Nushell Config File
#


# Default config
$env.config.color_config = {
    separator: white
    leading_trailing_space_bg: { attr: n }
    header: green_bold
    empty: blue
    bool: light_cyan
    int: white
    filesize: cyan
    duration: white
    datetime: purple
    range: white
    float: white
    string: white
    nothing: white
    binary: white
    cell-path: white
    row_index: green_bold
    record: white
    list: white
    closure: green_bold
    glob:cyan_bold
    block: white
    hints: dark_gray
    search_result: { bg: red fg: white }
    shape_binary: purple_bold
    shape_block: blue_bold
    shape_bool: light_cyan
    shape_closure: green_bold
    shape_custom: green
    shape_datetime: cyan_bold
    shape_directory: cyan
    shape_external: cyan
    shape_externalarg: green_bold
    shape_external_resolved: light_yellow_bold
    shape_filepath: cyan
    shape_flag: blue_bold
    shape_float: purple_bold
    shape_glob_interpolation: cyan_bold
    shape_globpattern: cyan_bold
    shape_int: purple_bold
    shape_internalcall: cyan_bold
    shape_keyword: cyan_bold
    shape_list: cyan_bold
    shape_literal: blue
    shape_match_pattern: green
    shape_matching_brackets: { attr: u }
    shape_nothing: light_cyan
    shape_operator: yellow
    shape_pipe: purple_bold
    shape_range: yellow_bold
    shape_record: cyan_bold
    shape_redirection: purple_bold
    shape_signature: green_bold
    shape_string: green
    shape_string_interpolation: cyan_bold
    shape_table: blue_bold
    shape_variable: purple
    shape_vardecl: purple
    shape_raw_string: light_purple
    shape_garbage: {
        fg: white
        bg: red
        attr: b
    }
}


# Remove Nushell's welcome message
# --------------------------------
$env.config.show_banner = false


# NU_LIB_DIRS
# -----------
# Directories in this environment variable are searched by the
# `use` and `source` commands.
# It is searched after the NU_LIB_DIRS constant.
#
$env.NU_LIB_DIRS ++= [ "/app/osm" ]


# Load the model and environment parameters
# -----------------------------------------
let clear_environment_location: path = ($env.CLEAR_ENVIRONMENT_LOCATION? | default "/model/parameters/clear/environment.yaml")
let secret_environment_location: path = ($env.SECRET_ENVIRONMENT_LOCATION? | default "/model/parameters/secret/environment.yaml")
let model_location: path = ($env.MODEL_LOCATION? | default "/model/app_instance_model.yaml")
let environment: record = (
    open $clear_environment_location | default {}
    | merge (
        open $secret_environment_location | default {}
    )
)
let model_instance: record = (open $model_location | default {})


# Load the required library
use /app/osm/operations/app.nu
