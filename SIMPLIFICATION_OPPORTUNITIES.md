# Simplification Opportunities

This document tracks potential simplification and consolidation opportunities identified during the codebase review.

## Completed ✅

### 1. @StateObject Dependency Consolidation ✅
- **Problem**: Every view duplicated `@StateObject` declarations for shared managers
- **Solution**: Consolidated to single source in MainTabView with `@EnvironmentObject` pattern
- **Impact**: Eliminated 7 duplicate declarations, cleaner child views

### 2. SessionManager Connection Logic ✅  
- **Problem**: 130+ lines of complex health checks, state verification, retry logic
- **Solution**: Direct WebSocket connection with simple 3-attempt retry
- **Impact**: Reduced to 30 lines, faster connections, easier debugging

### 3. TerminalViewModel State Duplication ✅
- **Problem**: 29 binding/sink patterns, redundant state copying from SessionManager
- **Solution**: Computed properties accessing SessionManager directly, single source of truth
- **Impact**: ~30 lines removed, no state sync bugs, cleaner architecture

### 4. Connection Status Reactivity ✅
- **Problem**: UI not updating when connection states changed
- **Solution**: Added `@Published connectionStates` and proper observation patterns
- **Impact**: Real-time status updates, better UX

### 5. Machine Selection Synchronization ✅
- **Problem**: UI selection vs actual connection state could get out of sync
- **Solution**: Ensured Connect button updates both UI and connection state
- **Impact**: Consistent selection behavior, terminal shows correct machine

## Remaining Opportunities

### 6. Error Handling Consolidation
- **Problem**: 105+ error-related occurrences with inconsistent patterns
  - Some views use `GroupBox` for errors
  - Some use inline text 
  - Some ignore errors entirely
  - No unified error display strategy
- **Potential Solution**: 
  - Create unified `ErrorView` component
  - Standardize error handling across all views
  - Consider centralized error management in a dedicated service
- **Estimated Impact**: More consistent UX, easier error debugging, ~20-30 lines saved

### 7. FlyAPIClient Further Consolidation
- **Status**: Already well-consolidated with `performRequest` method
- **Opportunity**: Could potentially merge similar API patterns further
- **Priority**: Low (already quite clean)

### 8. Binding Patterns Standardization
- **Problem**: Mix of `.sink`, `.assign`, and manual binding patterns
- **Opportunity**: Standardize on consistent Combine patterns
- **Estimated Impact**: More predictable code, easier maintenance

### 9. View Component Extraction
- **Problem**: `AgentsView.swift` is 429 lines with multiple responsibilities
- **Opportunity**: Extract reusable components like:
  - Machine status cards
  - Configuration sections  
  - Action button groups
- **Estimated Impact**: Better reusability, cleaner file organization

### 10. Shared Constants/Configuration
- **Problem**: Magic numbers and strings scattered throughout
  - Timeout values: 5s, 15s, 30s in different places
  - Color definitions duplicated
  - String literals for endpoints
- **Opportunity**: Create shared `Constants.swift` or configuration objects
- **Estimated Impact**: Easier maintenance, consistent behavior

## Anti-Patterns to Avoid

Based on our simplification work, avoid these patterns:

1. **State Duplication**: Don't copy `@Published` properties across classes
2. **Complex Binding Chains**: Prefer direct property access over elaborate `.sink` setups  
3. **Multiple Sources of Truth**: One class should own each piece of state
4. **Subscription Leaks**: Always clean up previous subscriptions in binding methods
5. **Threading Issues**: Use `MainActor.run` for UI updates from background threads

## Next Recommended Target

**Error Handling Consolidation (#6)** would provide the biggest UX improvement with moderate effort. It would create more consistent user experience and make debugging easier across the entire app.