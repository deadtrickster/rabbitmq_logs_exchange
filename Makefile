PROJECT = rabbitmq_logs_exchange

DEPS = rabbit mongodb mongodb_pool json
dep_mongodb_pool = git https://github.com/deadtrickster/mongodb-erlang-pool master
dep_json = git https://github.com/talentdeficit/json master
TEST_DEPS = amqp_client

DEP_PLUGINS = rabbit_common/mk/rabbitmq-build.mk \
	      rabbit_common/mk/rabbitmq-dist.mk \
	      rabbit_common/mk/rabbitmq-run.mk \
	      rabbit_common/mk/rabbitmq-test.mk \
	      rabbit_common/mk/rabbitmq-tools.mk

# FIXME: Use erlang.mk patched for RabbitMQ, while waiting for PRs to be
# reviewed and merged.

ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include rabbitmq-components.mk
include erlang.mk

NO_AUTOPATCH = 0
