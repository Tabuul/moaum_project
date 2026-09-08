package ng.edu.moaum.portal;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
@org.springframework.scheduling.annotation.EnableScheduling
public class PortalApiApplication {

	public static void main(String[] args) {
		SpringApplication.run(PortalApiApplication.class, args);
	}

}
