PROJECT = rabbitmq_logs_exchange

DEPS = rabbit mongodb mongodb_pool json
dep_mongodb_pool = git https://github.com/deadtrickster/mongodb-erlang-pool master
dep_json = git https://github.com/talentdeficit/json master
TEST_DEPS = amqp_client

DEP_PLUGINS = rabbit_common/mk/rabbitmq-plugin.mk

# FIXME: Use erlang.mk patched for RabbitMQ, while waiting for PRs to be
# reviewed and merged.

ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include rabbitmq-components.mk
include erlang.mk

# --------------------------------------------------------------------
# Testing.
# --------------------------------------------------------------------

WITH_BROKER_TEST_MAKEVARS := \
        RABBITMQ_CONFIG_FILE=$(CURDIR)/etc/rabbit-test
WITH_BROKER_TEST_COMMANDS := \
	rabbit_exchange_type_recent_history_test:test()
