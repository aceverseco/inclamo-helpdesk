# A release whose helpdesk starts and never becomes healthy: its migrations
# run, and its health page is gone. For the test of the rollback.
ARG BASE
FROM ${BASE}
RUN rm custom/app/controllers/inclamo/health_controller.rb
