#!/usr/bin/env -S nu --stdin
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


use std assert
# use ../../krm *

use ./location.nu *
use ./app.nu *
# use ./ksu.nu *
# use ./pattern.nu *
# use ./brick.nu *


# Test launcher
def main [] {
    print "Running tests..."

    let test_commands: list<string> = (
        scope commands
            | where ($it.type == "custom")
                and ($it.name | str starts-with "test ")
                and not ($it.description | str starts-with "ignore")
            | get name
    )

    let count_test_commands: int = ($test_commands | length)
    let test_commands_together: string = (
        $test_commands
        | enumerate
        | each { |test|
            [$"print '--> [($test.index + 1)/($count_test_commands)] ($test.item)'", $test.item]
        }
        | flatten
        | str join ";"
    )

    nu --commands $"source `($env.CURRENT_FILE)`; ($test_commands_together)"
    print $"\n✅ ALL TESTS COMPLETED SUCCESSFULLY"
}
