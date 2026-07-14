FROM maven:3.9.8-eclipse-temurin-17 AS build

WORKDIR /workspace
COPY pom.xml ./
COPY src ./src
RUN mvn -q -DskipTests package

FROM eclipse-temurin:17-jre AS runtime

WORKDIR /app

ARG TERRAFORM_VERSION=1.8.5
ARG TERRAFORM_SHA256=bb1ee3e8314da76658002e2e584f2d8854b6def50b7f124e27b957a42ddacfea

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSLo /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && echo "${TERRAFORM_SHA256}  /tmp/terraform.zip" | sha256sum -c - \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && rm -f /tmp/terraform.zip \
    && terraform version

RUN useradd --system --uid 10001 --create-home appuser
COPY --from=build /workspace/target/*.jar /tmp/
RUN set -eux; \
    JAR_PATH="$(find /tmp -maxdepth 1 -type f -name '*.jar' ! -name 'original-*.jar' | head -n 1)"; \
    test -n "$JAR_PATH"; \
    mv "$JAR_PATH" /app/app.jar; \
    rm -f /tmp/*.jar

USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD curl -fsS http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
