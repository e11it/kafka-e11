# Custom Kafka image with Aiven auth-for-apache-kafka plugin
# - Build stage uses Java 11 on UBI10 minimal
# - Fetches v4.7.1 source tarball and builds shaded jar
# Strimzi version: https://github.com/strimzi/strimzi-kafka-oauth
# nimbus - check pom file for strimzi
# Prometheus jmx: https://github.com/prometheus/jmx_exporter
# auth_for_kafka: https://github.com/Aiven-Open/auth-for-apache-kafka


ARG AUTH_FOR_KAFKA_VERSION=4.8.0
ARG PROMETHEUS_JMX_VERSION=1.5.0
ARG CP_KAFKA_VERSION=8.1.1
ARG KAFKA_VERSION=4.1.0
ARG STRIMZI_VERSION=0.17.1
ARG TS_VERSION=1.1.1
ARG RA_VERSION=1.0.2

#FROM eclipse-temurin:11-ubi10-minimal AS builder
FROM eclipse-temurin:21-ubi10-minimal AS builder
ARG AUTH_FOR_KAFKA_VERSION
ARG PROMETHEUS_JMX_VERSION
WORKDIR /src

ADD https://github.com/Aiven-Open/auth-for-apache-kafka/archive/refs/tags/v${AUTH_FOR_KAFKA_VERSION}.tar.gz /tmp/auth.tar.gz
RUN mkdir -p auth && tar -xzf /tmp/auth.tar.gz -C auth --strip-components=1 && rm -f /tmp/auth.tar.gz
WORKDIR /src/auth
RUN chmod +x gradlew \
    && ./gradlew --no-daemon clean -PkafkaVersion=${KAFKA_VERSION} shadowJar
WORKDIR /src/out
RUN mkdir -p libs && cp -v /src/auth/build/libs/*-all.jar libs/auth-for-apache-kafka-${AUTH_FOR_KAFKA_VERSION}.jar

# ##########################################################################################
FROM eclipse-temurin:17-ubi10-minimal AS builder2
ARG TS_VERSION

#WORKDIR /src
#ADD https://github.com/Aiven-Open/tiered-storage-for-apache-kafka/archive/refs/heads/main.tar.gz /tmp/main.tar.gz
#RUN mkdir -p app && tar -xzf /tmp/main.tar.gz -C app --strip-components=1 && rm -f /tmp/main.tar.gz
#WORKDIR /src/app
#ADD build.gradle .
#RUN chmod +x gradlew \
#   && ./gradlew build distTar -x test -x lint -x integrationTest -PkafkaVersion="${KAFKA_VERSION}" \
#   && ./gradlew build :storage:s3:distTar -x test -x lint -x integrationTest -PkafkaVersion="${KAFKA_VERSION}"
#
#WORKDIR /src/out
#RUN mkdir -p libs \
#   && ls /src/app/build/libs \
#   && cp -v /src/app/build/libs/tiered-storage-for-apache-kafka-1.2.0-SNAPSHOT.jar libs/ \
#   && cp -v /src/app/storage/build/libs/storage-1.2.0-SNAPSHOT.jar libs/
WORKDIR /src/out
RUN   mkdir -p /src/out/libs \
   && curl -k -L https://github.com/Aiven-Open/tiered-storage-for-apache-kafka/releases/download/v${TS_VERSION}/core-${TS_VERSION}.tgz -o core.tgz \
   && curl -k -L https://github.com/Aiven-Open/tiered-storage-for-apache-kafka/releases/download/v${TS_VERSION}/filesystem-${TS_VERSION}.tgz  -o filesystem.tgz \
   && curl -k -L https://github.com/Aiven-Open/tiered-storage-for-apache-kafka/releases/download/v${TS_VERSION}/s3-${TS_VERSION}.tgz -o s3.tgz

RUN ls -la ./ && tar -xzf core.tgz -C /src/out/libs \
    && tar -xzf filesystem.tgz -C /src/out/libs \
    && tar -xzf s3.tgz -C /src/out/libs

# ##########################################################################################
FROM confluentinc/cp-kafka:${CP_KAFKA_VERSION}
ARG PROMETHEUS_JMX_VERSION
ARG AUTH_FOR_KAFKA_VERSION

USER root
# Download and add Strimzi OAuth libraries
RUN curl -L -o /usr/share/java/kafka/strimzi-kafka-oauth-common-${STRIMZI_VERSION}.jar https://repo1.maven.org/maven2/io/strimzi/kafka-oauth-common/${STRIMZI_VERSION}/kafka-oauth-common-${STRIMZI_VERSION}.jar && \
 curl -L -o /usr/share/java/kafka/strimzi-kafka-oauth-server-${STRIMZI_VERSION}.jar https://repo1.maven.org/maven2/io/strimzi/kafka-oauth-server/${STRIMZI_VERSION}/kafka-oauth-server-${STRIMZI_VERSION}.jar && \
 curl -L -o /usr/share/java/kafka/strimzi-kafka-oauth-client-${STRIMZI_VERSION}.jar https://repo1.maven.org/maven2/io/strimzi/kafka-oauth-client/${STRIMZI_VERSION}/kafka-oauth-client-${STRIMZI_VERSION}.jar && \
 curl -L -o /usr/share/java/kafka/kafka-oauth-keycloak-authorizer-${STRIMZI_VERSION}.jar https://repo1.maven.org/maven2/io/strimzi/kafka-oauth-keycloak-authorizer/${STRIMZI_VERSION}/kafka-oauth-keycloak-authorizer-${STRIMZI_VERSION}.jar \
 && curl -L https://github.com/e11it/kafka-create-topic-policy/releases/download/v${RA_VERSION}/ra-${RA_VERSION}.jar -o /usr/share/java/kafka/ra-${RA_VERSION}.jar

# Download and add Nimbus JOSE+JWT library
RUN curl -L -o /usr/share/java/kafka/nimbus-jose-jwt-10.0.2.jar https://repo1.maven.org/maven2/com/nimbusds/nimbus-jose-jwt/10.0.2/nimbus-jose-jwt-10.0.1.jar

COPY --from=builder --chown=appuser:appuser /src/out/libs/auth-for-apache-kafka-${AUTH_FOR_KAFKA_VERSION}.jar /usr/share/java/kafka/auth-for-apache-kafka-${AUTH_FOR_KAFKA_VERSION}.jar
COPY --from=builder2 --chown=appuser:appuser /src/out/libs/*.jar /usr/share/java/kafka/
ADD --chown=appuser:appuser jmx/jmx_prometheus_javaagent-${PROMETHEUS_JMX_VERSION}.jar /opt/kafka/jmx/jmx_prometheus_javaagent-${PROMETHEUS_JMX_VERSION}.jar
ADD --chown=appuser:appuser jmx/kafka.yml /opt/kafka/jmx/kafka.yml

USER appuser
ADD --chown=appuser:appuser ./log4j2.yaml /etc/kafka_ext/log4j2.yaml
