FROM gradle:8.13-jdk17 AS build
WORKDIR /home/services/
COPY . .
RUN gradle :product-sv:clean :product-sv:bootJar --no-daemon -x test

FROM eclipse-temurin:17-jre-alpine
ARG JAVA_OPTS=""
WORKDIR /app
COPY --from=build /home/services/product-sv/build/libs/*.jar app.jar
EXPOSE 8082
ENTRYPOINT ["sh", "-c","exec java $JAVA_OPTS -jar app.jar"]
