# TODO: Known Issues and Future Improvements

## Java Backend Issues

### 1. Pagination Default Page Size
**Note**: Java uses a default page size of 50 (defined in `Constants.DEFAULT_PAGE_SIZE`), not 20 as the `MAX_PAGE_SIZE` constant might suggest.

**Details**:
- The `JobResource.java` class defines `MAX_PAGE_SIZE = 20` but this is never enforced
- The actual default page size is 50 from `Constants.DEFAULT_PAGE_SIZE`
- When no `page-size` parameter is provided, Java defaults to returning up to 50 jobs
- The `pageSizeRequested` value is passed directly to `jobDAO.getJobs()` without any MAX_PAGE_SIZE limit checking
- Users can request page sizes larger than MAX_PAGE_SIZE (20) and even larger than the default (50)

**Impact**: 
- Performance issues with large numbers of jobs
- UI becomes unwieldy with hundreds of jobs displayed on one page
- Memory consumption increases with job count

**Temporary Fix**: 
- Rails backend has been modified to match this buggy behavior for compatibility testing
- See `app/models/job.rb` - the `all` method returns all jobs when no pagination params are provided

**Proper Fix Would Involve**:
```java
// In JobResource.java, around line 131-136
final int pageSizeRequested = pageSize.isPresent() ? 
    Math.min(pageSize.get(), MAX_PAGE_SIZE) :  // Enforce MAX_PAGE_SIZE limit
    defaultPageSize;
```

## Test Issues

### Jobs Endpoint Comparison Test
The `testJobsEndpoint` test in compare mode fails because it compares exact job IDs in href links. Since:
- Both servers return the same jobs but in potentially different order
- Jobs may be created during test execution changing the list
- The sort order can differ for jobs with identical timestamps

The test should either:
- Sort both responses before comparison
- Exclude job-specific IDs from comparison (like other tests do)
- Compare structure only, not actual values

Both Rails and Java return structurally identical responses with the same jobs.

## Rails Backend Notes

### Compatibility Mode
The Rails backend has been modified to maintain compatibility with the Java backend's behavior, including replicating certain bugs. Once the Java backend is fully replaced, these compatibility workarounds can be removed:

1. **Pagination**: Currently returns all jobs when no pagination parameters are provided (matching Java bug)
2. **Link Generation**: Conditionally includes links based on file existence and size (matching Java behavior)
3. **Status Format**: Uses hyphens instead of underscores in status values (e.g., "fatal-error" not "fatal_error")
4. **Request.json Format**: Stores timestamps in request.json instead of separate file (Java format)