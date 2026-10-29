FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn -q package -DskipTests

FROM eclipse-temurin:21-jre
COPY --from=build /app/target/logs-api.jar app.jar
EXPOSE 8081
CMD ["java", "-jar", "app.jar"]
