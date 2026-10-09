FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn -q package -DskipTests

FROM eclipse-temurin:21-jre
COPY --from=build /app/target/dogs-api.jar app.jar
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
