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
 * 1. Start Rails server: cd src-rails && rails s -p 8081
 * 2. Run test: mvn test -Dtest=RailsCompatibilityTest
 * 
 * To run against Java backend:
 * 1. Set environment: export JOBSON_TEST_BACKEND=java
 * 2. Start Java server on port 8080
 * 3. Run test: mvn test -Dtest=RailsCompatibilityTest
 * 
 * To compare both backends (exact output matching):
 * 1. Set environment: export JOBSON_TEST_MODE=compare
 * 2. Start Java on port 8080 and Rails on port 8081
 * 3. Run test: mvn test -Dtest=RailsCompatibilityTest
 */
public class RailsCompatibilityTest {
    
    private static String API_BASE;
    private static String RAILS_API = "http://localhost:8081";
    private static String JAVA_API = "http://localhost:8080";
    private static boolean COMPARE_MODE = false;
    private static ObjectMapper mapper = new ObjectMapper();
    
    @BeforeClass
    public static void setup() throws Exception {
        String testMode = System.getenv("JOBSON_TEST_MODE");
        
        if ("compare".equals(testMode)) {
            COMPARE_MODE = true;
            System.out.println("=== EXACT COMPATIBILITY TEST MODE ===");
            System.out.println("Comparing Rails (" + RAILS_API + ") vs Java (" + JAVA_API + ")");
            System.out.println("Note: IDs and timestamps are excluded from comparison");
            System.out.println();
            
            // Print available endpoints to understand API structure
            System.out.println("Discovering API endpoints...");
            System.out.println("----------------------------------------");
            try {
                String railsRoot = httpGetQuiet(RAILS_API, "/");
                System.out.println("Rails / response: " + railsRoot);
                
                String javaRoot = httpGetQuiet(JAVA_API, "/");
                System.out.println("Java / response: " + javaRoot);
                
                String railsV1 = httpGetQuiet(RAILS_API, "/api/v1");
                System.out.println("Rails /api/v1 response: " + railsV1);
                
                String javaV1 = httpGetQuiet(JAVA_API, "/v1/");
                System.out.println("Java /v1/ response: " + javaV1);
                
                System.out.println("----------------------------------------");
                System.out.println("API Structure Summary:");
                System.out.println("  Rails: / -> /api/v1 -> /api/v1/specs, /api/v1/jobs");
                System.out.println("  Java:  / -> /v1/ -> /v1/specs, /v1/jobs");
                System.out.println("----------------------------------------");
                System.out.println();
            } catch (Exception e) {
                System.err.println("Warning: Could not discover all endpoints: " + e.getMessage());
            }
        } else {
            // Default to Rails backend on 8081, can override with env var
            String backend = System.getenv("JOBSON_TEST_BACKEND");
            if ("java".equals(backend)) {
                API_BASE = "http://localhost:8080"; // Java runs on 8080
                // Note: Java backend would need to be started separately
            } else {
                API_BASE = "http://localhost:8081"; // Rails backend on 8081
            }
            
            System.out.println("Testing against backend: " + API_BASE);
        }
    }
    
    private static String httpGetQuiet(String baseUrl, String endpoint) throws Exception {
        URL url = new URL(baseUrl + endpoint);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        conn.setRequestProperty("Accept", "application/json");
        
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
            return "HTTP " + responseCode;
        }
        
        return response.toString();
    }
    
    @Test
    public void testRootEndpoint() throws Exception {
        if (COMPARE_MODE) {
            System.out.println("Test 1: Root endpoint (/) exact comparison...");
            String railsResponse = httpGetFrom(RAILS_API, "/");
            String javaResponse = httpGetFrom(JAVA_API, "/");
            
            System.out.println("  Rails response: " + railsResponse);
            System.out.println("  Java response: " + javaResponse);
            
            JsonNode railsJson = mapper.readTree(railsResponse);
            JsonNode javaJson = mapper.readTree(javaResponse);
            
            assertJsonEquals("Root endpoint", railsJson, javaJson, new String[]{});
            System.out.println("  ✓ Root endpoint structures match exactly");
        } else {
            String response = httpGet("/");
            JsonNode json = mapper.readTree(response);
            
            assertNotNull("Root should have _links", json.get("_links"));
            assertNotNull("Root should have specs link", json.get("_links").get("specs"));
            assertNotNull("Root should have jobs link", json.get("_links").get("jobs"));
        }
    }
    
    @Test
    public void testV1RootEndpoint() throws Exception {
        if (COMPARE_MODE) {
            System.out.println("Test 2: API v1 endpoint comparison...");
            // Rails uses /api/v1 while Java uses /v1/
            String railsResponse = httpGetFrom(RAILS_API, "/api/v1");
            String javaResponse = httpGetFrom(JAVA_API, "/v1/");
            
            System.out.println("  Rails /api/v1 response: " + railsResponse);
            System.out.println("  Java /v1/ response: " + javaResponse);
            
            JsonNode railsJson = mapper.readTree(railsResponse);
            JsonNode javaJson = mapper.readTree(javaResponse);
            
            // Both should have the same structure with adjusted paths
            assertJsonEquals("v1 endpoint", railsJson, javaJson, new String[]{});
            System.out.println("  ✓ API v1 endpoint structures match");
        } else {
            String response = httpGet("/api/v1");
            JsonNode json = mapper.readTree(response);
            
            assertNotNull("V1 root should have _links", json.get("_links"));
            assertNotNull("V1 should have specs link", json.get("_links").get("specs"));
            assertNotNull("V1 should have jobs link", json.get("_links").get("jobs"));
        }
    }
    
    @Test
    public void testSpecsEndpoint() throws Exception {
        if (COMPARE_MODE) {
            System.out.println("Test 3: Specs endpoint comparison...");
            // Rails uses /api/v1/specs while Java uses /v1/specs
            String railsResponse = httpGetFrom(RAILS_API, "/api/v1/specs");
            String javaResponse = httpGetFrom(JAVA_API, "/v1/specs");
            
            System.out.println("  Rails response: " + railsResponse.substring(0, Math.min(100, railsResponse.length())));
            System.out.println("  Java response: " + javaResponse.substring(0, Math.min(100, javaResponse.length())));
            
            JsonNode railsJson = mapper.readTree(railsResponse);
            JsonNode javaJson = mapper.readTree(javaResponse);
            
            assertJsonEquals("specs endpoint", railsJson, javaJson, new String[]{});
            System.out.println("  ✓ Specs endpoint structures match");
        } else {
            String response = httpGet("/api/v1/specs");
            JsonNode json = mapper.readTree(response);
            
            assertNotNull("Specs response should have entries array", json.get("entries"));
            assertTrue("Entries should be an array", json.get("entries").isArray());
        }
    }
    
    @Test
    public void testJobsEndpoint() throws Exception {
        if (COMPARE_MODE) {
            System.out.println("Test 4: Jobs endpoint comparison...");
            // Rails uses /api/v1/jobs while Java uses /v1/jobs
            String railsResponse = httpGetFrom(RAILS_API, "/api/v1/jobs");
            String javaResponse = httpGetFrom(JAVA_API, "/v1/jobs");
            
            JsonNode railsJson = mapper.readTree(railsResponse);
            JsonNode javaJson = mapper.readTree(javaResponse);
            
            // Sort the entries arrays by job ID to ensure consistent comparison
            // Both servers return the same jobs but potentially in different order
            sortJobEntries(railsJson);
            sortJobEntries(javaJson);
            
            assertJsonEquals("jobs endpoint", railsJson, javaJson, new String[]{});
            System.out.println("  ✓ Jobs endpoint structures match");
        } else {
            String response = httpGet("/api/v1/jobs");
            JsonNode json = mapper.readTree(response);
            
            assertNotNull("Jobs response should have entries", json.get("entries"));
            assertTrue("Entries should be an array", json.get("entries").isArray());
        }
    }
    
    @Test
    public void testCreateAndGetJob() throws Exception {
        if (COMPARE_MODE) {
            System.out.println("Test 5: Job creation and retrieval exact comparison...");
            
            // Create identical job on both systems
            String jobRequest = "{\"name\":\"Test Job\",\"spec\":\"echo\",\"inputs\":{\"message\":\"Hello Test\"}}";
            
            System.out.println("  Creating job on Rails backend...");
            String railsCreateResponse = httpPostTo(RAILS_API, "/api/v1/jobs", jobRequest);
            JsonNode railsCreateJson = mapper.readTree(railsCreateResponse);
            String railsJobId = railsCreateJson.get("id").asText();
            
            System.out.println("  Creating job on Java backend...");
            // Java uses /v1/jobs instead of /api/v1/jobs
            String javaCreateResponse = httpPostTo(JAVA_API, "/v1/jobs", jobRequest);
            JsonNode javaCreateJson = mapper.readTree(javaCreateResponse);
            String javaJobId = javaCreateJson.get("id").asText();
            
            // Compare creation responses (excluding auto-generated fields)
            String[] excludeFields = {"id", "timestamp", "timestamps", "_links"};
            assertJsonEquals("Job creation response", railsCreateJson, javaCreateJson, excludeFields);
            System.out.println("  ✓ Job creation responses match (excluding IDs/timestamps)");
            
            // Get job details and compare
            System.out.println("  Retrieving and comparing job details...");
            String railsJobResponse = httpGetFrom(RAILS_API, "/api/v1/jobs/" + railsJobId);
            // Java uses /v1/jobs instead of /api/v1/jobs
            String javaJobResponse = httpGetFrom(JAVA_API, "/v1/jobs/" + javaJobId);
            
            JsonNode railsJobJson = mapper.readTree(railsJobResponse);
            JsonNode javaJobJson = mapper.readTree(javaJobResponse);
            
            assertJsonEquals("Job details", railsJobJson, javaJobJson, excludeFields);
            System.out.println("  ✓ Job details match (excluding IDs/timestamps)");
        } else {
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
    }
    
    // Helper methods for exact comparison mode
    private void assertJsonEquals(String context, JsonNode expected, JsonNode actual, String[] excludeFields) {
        // Deep copy to avoid modifying original nodes
        JsonNode expectedCopy = expected.deepCopy();
        JsonNode actualCopy = actual.deepCopy();
        
        // Remove excluded fields
        removeFields(expectedCopy, excludeFields);
        removeFields(actualCopy, excludeFields);
        
        // Compare structures
        compareJsonStructures(context, expectedCopy, actualCopy);
    }
    
    private void removeFields(JsonNode node, String[] fields) {
        if (node.isObject()) {
            for (String field : fields) {
                ((com.fasterxml.jackson.databind.node.ObjectNode) node).remove(field);
            }
            // Recursively remove from child nodes
            node.fields().forEachRemaining(entry -> removeFields(entry.getValue(), fields));
        } else if (node.isArray()) {
            for (JsonNode element : node) {
                removeFields(element, fields);
            }
        }
    }
    
    private void compareJsonStructures(String context, JsonNode expected, JsonNode actual) {
        assertEquals(context + ": Node types should match", 
                     expected.getNodeType(), actual.getNodeType());
        
        if (expected.isObject()) {
            // Compare field names
            java.util.List<String> expectedFields = new java.util.ArrayList<>();
            java.util.List<String> actualFields = new java.util.ArrayList<>();
            
            expected.fieldNames().forEachRemaining(expectedFields::add);
            actual.fieldNames().forEachRemaining(actualFields::add);
            
            expectedFields.sort(String::compareTo);
            actualFields.sort(String::compareTo);
            
            assertEquals(context + ": Field names should match", expectedFields, actualFields);
            
            // Recursively compare each field
            for (String field : expectedFields) {
                compareJsonStructures(context + "." + field, 
                                     expected.get(field), 
                                     actual.get(field));
            }
        } else if (expected.isArray()) {
            assertEquals(context + ": Array sizes should match", 
                        expected.size(), actual.size());
            
            for (int i = 0; i < expected.size(); i++) {
                compareJsonStructures(context + "[" + i + "]", 
                                     expected.get(i), 
                                     actual.get(i));
            }
        } else {
            // For primitive values
            assertEquals(context + ": Values should match", 
                        expected.asText(), actual.asText());
        }
    }
    
    // Helper methods for single backend testing
    private String httpGet(String endpoint) throws Exception {
        return httpGetFrom(API_BASE, endpoint);
    }
    
    private String httpPost(String endpoint, String jsonData) throws Exception {
        return httpPostTo(API_BASE, endpoint, jsonData);
    }
    
    // Helper methods for specific backend
    private String httpGetFrom(String baseUrl, String endpoint) throws Exception {
        URL url = new URL(baseUrl + endpoint);
        System.out.println("    GET " + url);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        conn.setRequestProperty("Accept", "application/json");
        
        return readResponse(conn);
    }
    
    private String httpPostTo(String baseUrl, String endpoint, String jsonData) throws Exception {
        URL url = new URL(baseUrl + endpoint);
        System.out.println("    POST " + url);
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