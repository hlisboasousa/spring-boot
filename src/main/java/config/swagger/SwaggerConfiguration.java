package config.swagger;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class SwaggerConfiguration {

    @Bean
    public OpenAPI customOpenAPI() {
        SecurityScheme securityScheme = new SecurityScheme()
                .type(SecurityScheme.Type.HTTP)
                .scheme("bearer").bearerFormat("JWT");

        Components components = new Components()
                .addSecuritySchemes("bearer-key", securityScheme);

        Info info = new Info()
                .version("1.0.0")
                .title("LLZ Garantidora - Administradora")
                .description("API Rest da aplicação LLZ Operation");

        return new OpenAPI().components(components).info(info);
    }
}
