# Copyright 2020 Canonical Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#     Unless required by applicable law or agreed to in writing, software
#     distributed under the License is distributed on an "AS IS" BASIS,
#     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#     See the License for the specific language governing permissions and
#     limitations under the License.
import json
import argparse

CHANNEL_LIST = [
    "stable",
    "candidate",
    "edge",
]
BUNDLE_PREFIX = "cs:~charmed-osm"
DEFAULT_BUNDLE = "bundles/osm/bundle.yaml"
HA_BUNDLE = "bundles/osm-ha/bundle.yaml"

parser = argparse.ArgumentParser(description="Process some arguments.")

parser.add_argument("--channel", help="Channel from the Charm Store")
parser.add_argument("--destination", help="Destination for the generated bundle")
parser.add_argument("--ha", help="Select HA bundle", action="store_true")
parser.add_argument("--local", help="Path to the bundle directory", action="store_true")
parser.add_argument("--store", help="Path to the bundle directory", action="store_true")

args = parser.parse_args()
print(args)
if not args.local and not args.store:
    raise Exception("--local or --store must be specified")
if args.local and args.store:
    raise Exception("Both --local and --store cannot be specified. Please choose one.")
if not args.destination:
    raise Exception("--destination must be specified")
if args.channel and not args.channel in CHANNEL_LIST:
    raise Exception(
        "Channel {} does not exist. Please choose one of these: {}".format(
            args.channel, CHANNEL_LIST
        )
    )
channel = args.channel if args.channel else "stable"
path = HA_BUNDLE if args.ha else DEFAULT_BUNDLE
destination = args.destination
prefix = "." if args.local else BUNDLE_PREFIX
suffix = "/build" if args.local else ""

data = {
    "channel": channel,
    "prefix": prefix,
    "suffix": suffix,
}

with open(path) as template:
    bundle_template = template.read()
    template.close()
with open("{}".format(destination), "w") as text_file:
    text_file.write(bundle_template % data)
    text_file.close()
