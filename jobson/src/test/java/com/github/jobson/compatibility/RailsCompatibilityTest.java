package com.github.jobson.compatibility;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import org.junit.Test;
import org.junit.BeforeClass;

import java.net.HttpURLConnection;
import java.net.URL;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;

import static org.junit.Assert.*;

/**
 * Tests to verify Rails API compatibility with Java Jobson API.
 * 
 * To run these tests against Rails backend:
 * 1. Start Rails server: cd src-rails && rails s -p 8080
 * 2. Run test: mvn test -Dtest=RailsCompatibilityTest
 * 
 * To run against Java backend:
 * 1. Set environment: export JOBSON_TEST_BACKEND=java
 * 2. The test will start the Java server automatically
 */
public class RailsCompatibilityTest {
    
    private static String API_BASE;
    private static ObjectMapper mapper = new ObjectMapper();
    
    @BeforeClass
    public static void setup() {
        // Default to Rails backend on 8080, can override with env var
        String backend = System.getenv("JOBSON_TEST_BACKEND");
        if ("java".equals(backend)) {
            API_BASE = "http://localhost:8081"; // Java typically runs on 8081 in tests
            // Note: Java backend would need to be started separately
        } else {
            API_BASE = "http://localhost:8080"; // Rails backend
        }
        
        System.out.println("Testing against backend: " + API_BASE);
    }
    
    @Test
    public void testRootEndpoint() throws Exception {
        String response = httpGet("/");
        JsonNode json = mapper.readTree(response);
        
        assertNotNull("Root should have _links", json.get("_links"));
        assertNotNull("Root should have specs link", json.get("_links").get("specs"));
        assertNotNull("Root should have jobs link", json.get("_links").get("jobs"));
    }
    
    @Test
    public void testV1RootEndpoint() throws Exception {
        String response = httpGet("/api/v1");
        JsonNode json = mapper.readTree(response);
        
        assertNotNull("V1 root should have _links", json.get("_links"));
        assertNotNull("V1 should have specs link", json.get("_links").get("specs"));
        assertNotNull("V1 should have jobs link", json.get("_links").get("jobs"));
    }
    
    @Test
    public void testSpecsEndpoint() throws Exception {
        String response = httpGet("/api/v1/specs");
        JsonNode json = mapper.readTree(response);
        
        assertNotNull("Specs response should have entries array", json.get("entries"));
        assertTrue("Entries should be an array", json.get("entries").isArray());
    }
    
    @Test
    public void testJobsEndpoint() throws Exception {
        String response = httpGet("/api/v1/jobs");
        JsonNode json = mapper.readTree(response);
        
        assertNotNull("Jobs response should have entries", json.get("entries"));
        assertTrue("Entries should be an array", json.get("entries").isArray());
    }
    
    @Test
    public void testCreateAndGetJob() throws Exception {
        // Create a job
        String jobRequest = "{\"name\":\"Test Job\",\"spec\":\"echo\",\"inputs\":{\"message\":\"Hello Test\"}}";
        String createResponse = httpPost("/api/v1/jobs", jobRequest);
        JsonNode createJson = mapper.readTree(createResponse);
        
        assertNotNull("Create should return job ID", createJson.get("id"));
        String jobId = createJson.get("id").asText();
        
        // Get job details
        String jobResponse = httpGet("/api/v1/jobs/" + jobId);
        JsonNode jobJson = mapper.readTree(jobResponse);
        
        assertEquals("Job ID should match", jobId, jobJson.get("id").asText());
        assertEquals("Job name should match", "Test Job", jobJson.get("name").asText());
        assertNotNull("Job should have timestamps", jobJson.get("timestamps"));
    }
    
    // Helper methods
    private String httpGet(String endpoint) throws Exception {
        URL url = new URL(API_BASE + endpoint);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        conn.setRequestProperty("Accept", "application/json");
        
        return readResponse(conn);
    }
    
    private String httpPost(String endpoint, String jsonData) throws Exception {
        URL url = new URL(API_BASE + endpoint);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("POST");
        conn.setRequestProperty("Content-Type", "application/json");
        conn.setRequestProperty("Accept", "application/json");
        conn.setDoOutput(true);
        
        OutputStreamWriter out = new OutputStreamWriter(conn.getOutputStream());
        out.write(jsonData);
        out.flush();
        out.close();
        
        return readResponse(conn);
    }
    
    private String readResponse(HttpURLConnection conn) throws Exception {
        int responseCode = conn.getResponseCode();
        
        BufferedReader in = new BufferedReader(new InputStreamReader(
            responseCode >= 200 && responseCode < 300 ? 
                conn.getInputStream() : conn.getErrorStream()
        ));
        
        String inputLine;
        StringBuilder response = new StringBuilder();
        while ((inputLine = in.readLine()) != null) {
            response.append(inputLine);
        }
        in.close();
        
        if (responseCode >= 400) {
            throw new RuntimeException("HTTP " + responseCode + ": " + response.toString());
        }
        
        return response.toString();
    }
}