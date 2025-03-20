# -*- coding: utf-8 -*-

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

import asyncio
import logging

from aiokafka import AIOKafkaConsumer
from aiokafka import AIOKafkaProducer
from aiokafka.errors import KafkaError
from osm_common.msgbase import MsgBase, MsgException
import yaml

__author__ = (
    "Alfonso Tierno <alfonso.tiernosepulveda@telefonica.com>, "
    "Guillermo Calvino <guillermo.calvinosanchez@altran.com>"
)


class MsgKafka(MsgBase):
    def __init__(self, logger_name="msg", lock=False):
        super().__init__(logger_name, lock)
        self.host = None
        self.port = None
        self.consumer = None
        self.producer = None
        self.broker = None
        self.group_id = None

    def connect(self, config):
        try:
            if "logger_name" in config:
                self.logger = logging.getLogger(config["logger_name"])
            self.host = config["host"]
            self.port = config["port"]
            self.broker = str(self.host) + ":" + str(self.port)
            self.group_id = config.get("group_id")

        except Exception as e:  # TODO refine
            raise MsgException(str(e))

    def disconnect(self):
        try:
            pass
        except Exception as e:  # TODO refine
            raise MsgException(str(e))

    def write(self, topic, key, msg):
        """
        Write a message at kafka bus
        :param topic: message topic, must be string
        :param key: message key, must be string
        :param msg: message content, can be string or dictionary
        :return: None or raises MsgException on failing
        """
        retry = 2  # Try two times
        while retry:
            try:
                asyncio.run(self.aiowrite(topic=topic, key=key, msg=msg))
                break
            except Exception as e:
                retry -= 1
                if retry == 0:
                    raise MsgException(
                        "Error writing {} topic: {}".format(topic, str(e))
                    )

    def read(self, topic):
        """
        Read from one or several topics.
        :param topic: can be str: single topic; or str list: several topics
        :return: topic, key, message; or None
        """
        try:
            return asyncio.run(self.aioread(topic))
        except MsgException:
            raise
        except Exception as e:
            raise MsgException("Error reading {} topic: {}".format(topic, str(e)))

    async def aiowrite(self, topic, key, msg):
        """
        Asyncio write
        :param topic: str kafka topic
        :param key: str kafka key
        :param msg: str or dictionary  kafka message
        :return: None
        """
        try:
            self.producer = AIOKafkaProducer(
                key_serializer=str.encode,
                value_serializer=str.encode,
                bootstrap_servers=self.broker,
            )
            await self.producer.start()
            await self.producer.send(
                topic=topic, key=key, value=yaml.safe_dump(msg, default_flow_style=True)
            )
        except Exception as e:
            raise MsgException(
                "Error publishing topic '{}', key '{}': {}".format(topic, key, e)
            )
        finally:
            await self.producer.stop()

    async def aioread(
        self,
        topic,
        callback=None,
        aiocallback=None,
        group_id=None,
        from_beginning=None,
        **kwargs
    ):
        """
        Asyncio read from one or several topics.
        :param topic: can be str: single topic; or str list: several topics
        :param callback: synchronous callback function that will handle the message in kafka bus
        :param aiocallback: async callback function that will handle the message in kafka bus
        :param group_id: kafka group_id to use. Can be False (set group_id to None), None (use general group_id provided
                         at connect inside config), or a group_id string
        :param from_beginning: if True, messages will be obtained from beginning instead of only new ones.
                               If group_id is supplied, only the not processed messages by other worker are obtained.
                               If group_id is None, all messages stored at kafka are obtained.
        :param kwargs: optional keyword arguments for callback function
        :return: If no callback defined, it returns (topic, key, message)
        """
        if group_id is False:
            group_id = None
        elif group_id is None:
            group_id = self.group_id
        try:
            if isinstance(topic, (list, tuple)):
                topic_list = topic
            else:
                topic_list = (topic,)
            self.consumer = AIOKafkaConsumer(
                bootstrap_servers=self.broker,
                group_id=group_id,
                auto_offset_reset="earliest" if from_beginning else "latest",
            )
            await self.consumer.start()
            self.consumer.subscribe(topic_list)

            async for message in self.consumer:
                if callback:
                    callback(
                        message.topic,
                        yaml.safe_load(message.key),
                        yaml.safe_load(message.value),
                        **kwargs
                    )
                elif aiocallback:
                    await aiocallback(
                        message.topic,
                        yaml.safe_load(message.key),
                        yaml.safe_load(message.value),
                        **kwargs
                    )
                else:
                    return (
                        message.topic,
                        yaml.safe_load(message.key),
                        yaml.safe_load(message.value),
                    )
        except KafkaError as e:
            raise MsgException(str(e))
        finally:
            await self.consumer.stop()
