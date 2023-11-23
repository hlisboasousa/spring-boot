package com.test;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@SpringBootApplication
@RestController

public class Main {
    public static void main(String[] args) {
        SpringApplication.run(Main.class, args);
    }

    @GetMapping("/test")
    public String TestMethod() {
        return "response";
    }
    @GetMapping("/greet")
    public GreetResponse greet() {
        GreetResponse response = new GreetResponse(
                "Hello",
                List.of("Java", "Golang", "Javascript"),
                new Person("Henrique")
        );
        return response;
    }

    record Person(String name) {
    }

    record GreetResponse(String greet, List<String> favProgrammingLanguages, Person person) {
    }

}

