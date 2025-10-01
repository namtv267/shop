FROM gradle:8.13-jdk17 AS build
WORKDIR /home/services/
COPY . .
RUN gradle :order-sv:clean :order-sv:bootJar --no-daemon -x test

FROM eclipse-temurin:17-jre-alpine
ARG JAVA_OPTS=""
WORKDIR /app
COPY --from=build /home/services/order-sv/build/libs/*.jar app.jar
EXPOSE 8083
ENTRYPOINT ["sh", "-c","exec java $JAVA_OPTS -jar app.jar"]
