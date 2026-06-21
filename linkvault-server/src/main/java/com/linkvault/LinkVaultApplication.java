package com.linkvault;

import com.anji.captcha.config.AjCaptchaAutoConfiguration;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.ImportAutoConfiguration;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
@ImportAutoConfiguration(AjCaptchaAutoConfiguration.class)
public class LinkVaultApplication {

    public static void main(String[] args) {
        SpringApplication.run(LinkVaultApplication.class, args);
    }
}
