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

# Module with custom functions to manage KSUs and their renderization of the corresponding ResourceList into a given target folder.


# Imports
use std assert
use ../location.nu *


### to path components tests ###

export def "test location to path components repo-path with base-path" [] {
    let input: record = {
        "repo-path": ["/custom/repo"],
        "base-path": ["base/dir"],  # Now unused in base construction
        "relative-path": ["file.txt"]
    }
    let actual: list<string> = ($input | to path components)
    let expected: list<string> = [ "/custom/repo" "base/dir" "file.txt" ]
    assert equal $actual $expected
}


export def "test location to path components repo-path with base-path with strings" [] {
    let input: record = {
        "repo-path": "/custom/repo",
        "base-path": "base/dir",  # Now unused in base construction
        "relative-path": "file.txt"
    }
    let actual: list<string> = ($input | to path components)
    let expected: list<string> = [ "/custom/repo" "base/dir" "file.txt" ]
    assert equal $actual $expected
}


export def "test location to path components explicit base-path usage" [] {
    let input: record = {
        "repo-name": "my_repo",
        "base-path": "explicit/base",
        "relative-path": "data.csv"
    }
    let actual: list<string> = ($input | to path components)
    let expected: list<string> = [ "/repos/my_repo" "explicit/base" "data.csv" ]
    assert equal $actual $expected
}


export def "test location to path components empty repo-name errors" [] {
    let input: record = {
        "repo-name": "",
        "relative-path": "file.txt"
    }
    assert error { $input | to path components }
}


export def "test location to path components partial profile spec errors" [] {
    let input: record = {
        "repo-path": "/valid/repo",
        "profile-type": "dev",
        "relative-path": "file.txt"
    }
    assert error { $input | to path components }
}


export def "test location to path components mixed spec priorities" [] {
    let input: record = {
        "repo-path": "/primary/repo",
        "repo-name": "secondary",
        "base-path": "explicit_base",
        "oka-type": "models",
        "oka-name": "ai",
        "relative-path": "config.yaml"
    }
    let actual: list<string> = ($input | to path components)
    let expected: list<string> = [ "/primary/repo" "explicit_base" "config.yaml" ]
    assert equal $actual $expected
}


# Updated existing tests with clearer names
export def "test location to path components profile-based with normalization" [] {
    let input: record = {
        "repo-name": "profile_repo",
        "profile-type": "PROD",
        "profile-name": "EU_Cluster",
        "relative-path": "secrets.env"
    }
    let actual: list<string> = ($input | to path components)
    let expected: list<string> = [ "/repos/profile_repo" "osm_admin/PROD/EU_Cluster" "secrets.env" ]
    assert equal $actual $expected
}


export def "test location to path components oka-based with normalization" [] {
    let input: record = {
        "repo-path": "/repos/oka_repo",
        "oka-type": "DATA",
        "oka-name": "Census2025",
        "relative-path": "demographics.csv"
    }
    let actual: list<string> = ($input | to path components)
    let expected: list<string> = [ "/repos/oka_repo" "DATA/Census2025" "demographics.csv" ]
    assert equal $actual $expected
}


# TODO:

### to absolute path tests ###

export def "test location to absolute path basic repo-path" [] {
    let input: record = {
        "repo-path": ["/main/repo", "sw-catalogs"],
        "base-path": ["apps", "example1"],
        "relative-path": ["manifests", "main-pattern", "main-brick-manifests"]
    }
    let actual: string = ($input | to absolute path)
    let expected: string = "/main/repo/sw-catalogs/apps/example1/manifests/main-pattern/main-brick-manifests"
    assert equal $actual $expected
}


export def "test location to absolute path profile-based with defaults" [] {
    let input: record = {
        "repo-name": "fleet",
        "profile-type": "dev",
        "profile-name": "TestEnv",
        "relative-path": ["app_instance01", "main"]
    }
    let actual = ($input | to absolute path)
    let expected = "/repos/fleet/osm_admin/dev/TestEnv/app_instance01/main"
    assert equal $actual $expected
}


export def "test location to absolute path oka-based with custom defaults" [] {
    let input: record = {
        "repo-name": "data_repo",
        "oka-type": "app",  # It should be converted to "apps"
        "oka-name": "upf",
        "relative-path": ["2024", "main"]
    }
    let actual: string = ($input | to absolute path "geo" "/data")
    let expected: string = "/data/data_repo/apps/upf/2024/main"
    assert equal $actual $expected
}


export def "test location to absolute path mixed specifications priority" [] {
    let input: record = {
        "repo-name": "fleet",
        "base-path": ["my_oka"],
        "relative-path": ["manifests"]
    }
    let actual: string = ($input | to absolute path)
    let expected: string = "/repos/fleet/my_oka/manifests"
    assert equal $actual $expected
}


export def "test location to absolute path special characters handling" [] {
    let input: record = {
        "repo-name": "fleet",
        "profile-type": "apps",     # Should become "app-profiles"
        "profile-name": "mycluster01",
        "relative-path": ["configs/prod"]
    }
    let actual: string = ($input | to absolute path)
    let expected: string = "/repos/fleet/osm_admin/app-profiles/mycluster01/configs/prod"
    assert equal $actual $expected
}


export def "test location to absolute path error missing relative-path" [] {
    let input: record = {
        "repo-path": ["/valid/repo"],
        "base-path": ["valid/base"]
    }
    assert error { $input | to absolute path }
}


export def "test location to absolute path nested relative path" [] {
    let input: record = {
        "repo-path": ["/repos/core"],
        "oka-type": "infra-controllers",
        "oka-name": "predictive",
        "relative-path": ["mobile", "serverless-web"]
    }
    let actual: string = ($input | to absolute path)
    let expected: string = "/repos/core/infra-controllers/predictive/mobile/serverless-web"
    assert equal $actual $expected
}


export def "test location to absolute path empty repo-name error" [] {
    let input: record = {
        "repo-name": "",
        "relative-path": ["file.txt"]
    }
    assert error { $input | to absolute path }
}


export def "test location to absolute path minimal valid input" [] {
    let input: record = {
        "repo-name": "fleet",
        "base-path": ["apps"],
        "relative-path": ["test-app"]
    }
    let actual: string = ($input | to absolute path)
    let expected: string = "/repos/fleet/apps/test-app"
    assert equal $actual $expected
}
