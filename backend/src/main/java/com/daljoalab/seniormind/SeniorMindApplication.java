package com.daljoalab.seniormind;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class SeniorMindApplication {
    public static void main(String[] args) {
        SpringApplication.run(SeniorMindApplication.class, args);
    }
}
