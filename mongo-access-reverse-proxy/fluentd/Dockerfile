FROM fluent/fluentd:v1.16-1
USER root

# Cài plugin gửi log sang Elasticsearch v7
RUN gem install fluent-plugin-elasticsearch -v 6.0.0 --no-document && \
    gem install fluent-plugin-record-modifier --no-document && \
    apk add --no-cache tzdata

# Sao chép cấu hình
COPY fluent.conf /fluentd/etc/fluent.conf

USER fluent
