package com.github.jobson.compatibility;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.Test;
import org.junit.BeforeClass;
import org.junit.AfterClass;

import java.net.HttpURLConnection;
import java.net.URL;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.util.Iterator;
import java.util.Map;
import java.util.ArrayList;
import java.util.List;

import static org.junit.Assert.*;

/**
 * Tests that verify Rails and Java APIs produce EXACTLY the same output
 * (except for auto-generated IDs and timestamps).
 * 
 * Usage:
 * 1. Start both servers:
 *    - Rails: cd src-rails && rails s -p 8080
 *    - Java: java -jar target/jobson.jar serve config.yml (on port 8081)
 * 2. Run: mvn test -Dtest=ExactCompatibilityTest
 */
public class ExactCompatibilityTest {
    
    private static final String RAILS_API = "http://localhost:8080";
    private static final String JAVA_API = "http://localhost:8081";
    private static ObjectMapper mapper = new ObjectMapper();
    
    @BeforeClass
    public static void setup() {
        System.out.println("=== EXACT API COMPATIBILITY TEST ===");
        System.out.println("Comparing Rails (" + RAILS_API + ") vs Java (" + JAVA_API + ")");
        System.out.println();
    }
    
    @Test
    public void testRootEndpointExactMatch() throws Exception {
        System.out.println("Testing: Root endpoint (/)...");
        
        String railsResponse = httpGet(RAILS_API, "/");
        String javaResponse = httpGet(JAVA_API, "/");
        
        JsonNode railsJson = mapper.readTree(railsResponse);
        JsonNode javaJson = mapper.readTree(javaResponse);
        
        compareJsonStructures("Root endpoint", railsJson, javaJson, new String[]{});
        System.out.println("  ✓ Root endpoint structures match exactly");
    }
    
    @Test
    public void testV1EndpointExactMatch() throws Exception {
        System.out.println("Testing: API v1 endpoint (/api/v1)...");
        
        String railsResponse = httpGet(RAILS_API, "/api/v1");
        String javaResponse = httpGet(JAVA_API, "/api/v1");
        
        JsonNode railsJson = mapper.readTree(railsResponse);
        JsonNode javaJson = mapper.readTree(javaResponse);
        
        compareJsonStructures("/api/v1", railsJson, javaJson, new String[]{});
        System.out.println("  ✓ API v1 endpoint structures match exactly");
    }
    
    @Test
    public void testSpecsEndpointExactMatch() throws Exception {
        System.out.println("Testing: Specs endpoint (/api/v1/specs)...");
        
        String railsResponse = httpGet(RAILS_API, "/api/v1/specs");
        String javaResponse = httpGet(JAVA_API, "/api/v1/specs");
        
        JsonNode railsJson = mapper.readTree(railsResponse);
        JsonNode javaJson = mapper.readTree(javaResponse);
        
        // Specs might have different ordering, so we need to compare structure
        compareJsonStructures("/api/v1/specs", railsJson, javaJson, new String[]{});
        System.out.println("  ✓ Specs endpoint structures match");
    }
    
    @Test
    public void testEmptyJobsListExactMatch() throws Exception {
        System.out.println("Testing: Empty jobs list (/api/v1/jobs)...");
        
        String railsResponse = httpGet(RAILS_API, "/api/v1/jobs");
        String javaResponse = httpGet(JAVA_API, "/api/v1/jobs");
        
        JsonNode railsJson = mapper.readTree(railsResponse);
        JsonNode javaJson = mapper.readTree(javaResponse);
        
        compareJsonStructures("/api/v1/jobs", railsJson, javaJson, new String[]{});
        System.out.println("  ✓ Jobs list structures match");
    }
    
    @Test
    public void testJobCreationAndRetrievalExactMatch() throws Exception {
        System.out.println("Testing: Job creation and retrieval...");
        
        // Create identical job on both systems
        String jobRequest = "{\"name\":\"Test Job\",\"spec\":\"echo\",\"inputs\":{\"message\":\"Hello Test\"}}";
        
        System.out.println("  Creating job on Rails backend...");
        String railsCreateResponse = httpPost(RAILS_API, "/api/v1/jobs", jobRequest);
        JsonNode railsCreateJson = mapper.readTree(railsCreateResponse);
        String railsJobId = railsCreateJson.get("id").asText();
        
        System.out.println("  Creating job on Java backend...");
        String javaCreateResponse = httpPost(JAVA_API, "/api/v1/jobs", jobRequest);
        JsonNode javaCreateJson = mapper.readTree(javaCreateResponse);
        String javaJobId = javaCreateJson.get("id").asText();
        
        // Compare creation responses (excluding auto-generated fields)
        String[] excludeFields = {"id", "timestamp", "timestamps", "_links"};
        compareJsonStructures("Job creation response", railsCreateJson, javaCreateJson, excludeFields);
        System.out.println("  ✓ Job creation responses match (excluding IDs/timestamps)");
        
        // Get job details and compare
        System.out.println("  Retrieving job details...");
        String railsJobResponse = httpGet(RAILS_API, "/api/v1/jobs/" + railsJobId);
        String javaJobResponse = httpGet(JAVA_API, "/api/v1/jobs/" + javaJobId);
        
        JsonNode railsJobJson = mapper.readTree(railsJobResponse);
        JsonNode javaJobJson = mapper.readTree(javaJobResponse);
        
        compareJsonStructures("Job details", railsJobJson, javaJobJson, excludeFields);
        System.out.println("  ✓ Job details match (excluding IDs/timestamps)");
    }
    
    @Test
    public void testErrorResponsesExactMatch() throws Exception {
        System.out.println("Testing: Error responses...");
        
        // Test 404 for non-existent job
        System.out.println("  Testing 404 for non-existent job...");
        try {
            httpGet(RAILS_API, "/api/v1/jobs/nonexistent");
            fail("Rails should return 404");
        } catch (RuntimeException e) {
            assertTrue(e.getMessage().contains("404"));
        }
        
        try {
            httpGet(JAVA_API, "/api/v1/jobs/nonexistent");
            fail("Java should return 404");
        } catch (RuntimeException e) {
            assertTrue(e.getMessage().contains("404"));
        }
        System.out.println("  ✓ Both return 404 for non-existent resources");
        
        // Test invalid job creation
        System.out.println("  Testing invalid job creation...");
        String invalidJob = "{\"invalid\":\"data\"}";
        
        try {
            httpPost(RAILS_API, "/api/v1/jobs", invalidJob);
            fail("Rails should reject invalid job");
        } catch (RuntimeException e) {
            assertTrue(e.getMessage().contains("400") || e.getMessage().contains("422"));
        }
        
        try {
            httpPost(JAVA_API, "/api/v1/jobs", invalidJob);
            fail("Java should reject invalid job");
        } catch (RuntimeException e) {
            assertTrue(e.getMessage().contains("400") || e.getMessage().contains("422"));
        }
        System.out.println("  ✓ Both reject invalid requests");
    }
    
    /**
     * Compare two JSON structures, ignoring specified fields
     */
    private void compareJsonStructures(String context, JsonNode rails, JsonNode java, String[] excludeFields) {
        // Check node types match
        assertEquals(context + ": Node types should match", 
                     rails.getNodeType(), java.getNodeType());
        
        if (rails.isObject()) {
            ObjectNode railsObj = (ObjectNode) rails;
            ObjectNode javaObj = (ObjectNode) java;
            
            // Remove excluded fields for comparison
            for (String field : excludeFields) {
                railsObj.remove(field);
                javaObj.remove(field);
            }
            
            // Check all fields exist in both
            List<String> railsFields = new ArrayList<>();
            List<String> javaFields = new ArrayList<>();
            
            Iterator<String> railsIt = railsObj.fieldNames();
            while (railsIt.hasNext()) railsFields.add(railsIt.next());
            
            Iterator<String> javaIt = javaObj.fieldNames();
            while (javaIt.hasNext()) javaFields.add(javaIt.next());
            
            // Sort for consistent comparison
            railsFields.sort(String::compareTo);
            javaFields.sort(String::compareTo);
            
            assertEquals(context + ": Field names should match", railsFields, javaFields);
            
            // Recursively compare each field
            for (String field : railsFields) {
                compareJsonStructures(context + "." + field, 
                                     railsObj.get(field), 
                                     javaObj.get(field), 
                                     excludeFields);
            }
        } else if (rails.isArray()) {
            assertEquals(context + ": Array sizes should match", 
                        rails.size(), java.size());
            
            // For arrays, we might need to handle ordering differences
            // For now, assume same order
            for (int i = 0; i < rails.size(); i++) {
                compareJsonStructures(context + "[" + i + "]", 
                                     rails.get(i), 
                                     java.get(i), 
                                     excludeFields);
            }
        } else {
            // For primitive values, check if they're in exclude list
            // Otherwise they should match exactly
            if (!isExcludedValue(rails, java, excludeFields)) {
                assertEquals(context + ": Values should match", 
                            rails.asText(), java.asText());
            }
        }
    }
    
    private boolean isExcludedValue(JsonNode rails, JsonNode java, String[] excludeFields) {
        // This is a simplified check - you might want to make this more sophisticated
        return false;
    }
    
    // Helper methods
    private String httpGet(String baseUrl, String endpoint) throws Exception {
        URL url = new URL(baseUrl + endpoint);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        conn.setRequestProperty("Accept", "application/json");
        
        return readResponse(conn);
    }
    
    private String httpPost(String baseUrl, String endpoint, String jsonData) throws Exception {
        URL url = new URL(baseUrl + endpoint);
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