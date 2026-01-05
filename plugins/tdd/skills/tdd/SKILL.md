---
name: tdd
description: >-
  Red-Green-Refactor test workflow with telemetry verification.
  MANDATORY for ALL AL test work - invoke proactively.
  CRITICAL RULE: DEBUG-* telemetry must be ZERO at both task START and END.
  Adds temporary DEBUG-TEST-START markers during Red phase, verifies execution
  in telemetry.jsonl during Green phase, removes all DEBUG-* during Refactor.
  The agent MUST invoke this skill whenever test-related work is detected,
  even if the user does not explicitly request it. (project)
---

# Red-Green-Refactor Test Development

## DEBUG Telemetry is Always Temporary

**Expected starting state:** Zero `DEBUG-*` telemetry calls in both production code (`app/src/`) and test code (`test/src/`).

**Why:** DEBUG telemetry is temporary scaffolding for proving code paths during development. It is NOT production instrumentation. If you find existing DEBUG-* calls, they indicate incomplete previous work.

**Lifecycle:**
1. Start clean (expect no DEBUG-* anywhere)
2. Add DEBUG-* calls during Red phase to prove execution
3. Verify in telemetry.jsonl during Green phase
4. **Remove ALL DEBUG-* calls during Refactor phase** (REQUIRED)
5. End clean (no DEBUG-* anywhere)

**If you find existing DEBUG-* calls:**
- Complete the previous work (remove them after verification), OR
- Remove them immediately if they're orphaned from abandoned work

## Assertions vs DEBUG Telemetry

**They verify different things:**

| Tool | Verifies | Question Answered |
|------|----------|-------------------|
| Assertions | Production code behavior | "Does the code produce correct output?" |
| DEBUG telemetry | Test setup correctness | "Did we exercise the intended code path?" |

**The False Positive Problem:**

Assertions can pass even when test setup is wrong. Example:
- Test intends to verify "Sales Line branch" produces Quantity=7
- Assertion passes: `Assert.AreEqual(7, ActualQuantity)`
- But test setup was wrong—code actually took the "Config Header branch"
- That branch also happened to produce Quantity=7 (coincidence)
- Without production telemetry, you cannot detect this

**Solution: Production code telemetry proves which path ran:**
- `DEBUG-TEST-START` in test → identifies which test is running
- `DEBUG-*` in production → proves which branch executed
- Correlation → confirms "Test X exercised code path Y"

## Quick Start

**Every test procedure you write MUST include:**
```al
FeatureTelemetry.LogUsage('DEBUG-TEST-START', 'Testing', '<ExactProcedureName>');
```
as the FIRST line after variable declarations. This is non-negotiable.

## Core rule
Telemetry verification is manual—do not add telemetry parsing/assertions to AL tests.

## Mandatory: Test-Start Telemetry Checkpoint

Every test procedure MUST begin with a telemetry checkpoint immediately after variable declarations:

```al
[Test]
procedure GivenX_WhenY_ThenZ()
var
    FeatureTelemetry: Codeunit "Feature Telemetry";
    // other variables...
begin
    // FIRST LINE - Always add this checkpoint
    FeatureTelemetry.LogUsage('DEBUG-TEST-START', 'Testing', 'GivenX_WhenY_ThenZ');

    // [SCENARIO] ...
    // [GIVEN] ...
    // [WHEN] ...
    // [THEN] ...
end;
```

### Why Test-Start Telemetry is Critical

Production code telemetry (e.g., pricing calculations, rule evaluations) can emit from multiple tests. Without test-start markers:
- Cannot determine which test triggered a specific log entry
- Cannot correlate DEBUG-* checkpoints in production code to the test that exercised them
- Cannot isolate test failures when multiple tests touch the same code paths

With test-start markers in `telemetry.jsonl`:
```json
{"eventId":"DEBUG-TEST-START","message":"GivenX_WhenY_ThenZ",...}
{"eventId":"DEBUG-PRICING-CALC","message":"Configuration method selected",...}
{"eventId":"DEBUG-COMPONENT-TOTAL","message":"Sum: 150.00",...}
```

Now you can grep for your test name and see all subsequent logs belong to that test.

## Workflow

### 1) Red: add temporary telemetry checkpoints

**Step A (REQUIRED):** Add test-start checkpoint as FIRST line after declarations:
```al
FeatureTelemetry.LogUsage('DEBUG-TEST-START', 'Testing', '<ExactProcedureName>');
```

**Step B (REQUIRED):** Add branch checkpoints in PRODUCTION code at decision points:
```al
// In the function under test (production code)
if SalesLine.FindFirst() then begin
    FeatureTelemetry.LogUsage('DEBUG-BRANCH-SALESLINE', 'FeatureName', 'Sales Line found');
    // ... Sales Line path
end else begin
    FeatureTelemetry.LogUsage('DEBUG-BRANCH-NOSALESLINE', 'FeatureName', 'Using Config Header');
    // ... Config Header path
end;
```

Rules:
- Use `FeatureTelemetry.LogUsage()` (not `Session.LogMessage()`)
- Use exact procedure name in test-start for grep-ability
- Keep event IDs stable and searchable (DEBUG-TEST-START, DEBUG-BRANCH-*)
- Use `Format()` for non-text values in custom dimensions
- Production code markers are REQUIRED—they verify test setup correctness

### 2) Green: make it pass and prove the path
1. Run the full test gate (see skill `al-build`)
2. Confirm test pass/fail in `.output/TestResults/last.xml`
3. Manually confirm expected branch ran in `.output/TestResults/telemetry.jsonl`

Useful telemetry fields: `eventId`, `message`, `testCodeunit`, `testProcedure`, `callStack`, `customDimensions`

### 3) Refactor: remove temporary logs

Once tests are verified and green, delete **all** `DEBUG-*` telemetry from both locations:

**Production code:**
- Remove branch checkpoints (e.g., `DEBUG-PRICING-CALC`, `DEBUG-COMPONENT-TOTAL`)
- Keep only long-lived production instrumentation (non-DEBUG event IDs)

**Test code:**
- Remove test-start checkpoints (`DEBUG-TEST-START`)
- Remove any other `DEBUG-*` calls added for verification

Both must be cleaned up—leaving DEBUG telemetry in either location pollutes logs and signals incomplete work.

## Analyzing Telemetry Correlation

After running tests, correlate logs to specific tests:

```powershell
# Find all logs from a specific test
Select-String -Path .output/TestResults/telemetry.jsonl -Pattern "GivenX_WhenY_ThenZ"

# Find test-start markers to see test execution order
Select-String -Path .output/TestResults/telemetry.jsonl -Pattern "DEBUG-TEST-START"
```

In `telemetry.jsonl`, logs appear in execution order. After a `DEBUG-TEST-START` entry, all subsequent logs belong to that test until the next `DEBUG-TEST-START`.

## Telemetry Correlation Example

After running tests, `telemetry.jsonl` shows execution order:

```
Test 1: GivenSalesLineExists...
  DEBUG-TEST-START → GivenSalesLineExists...
  DEBUG-BRANCH-SALESLINE → Sales Line found     ✓ Correct path

Test 2: GivenNoSalesLine...
  DEBUG-TEST-START → GivenNoSalesLine...
  DEBUG-BRANCH-NOSALESLINE → Using Config Header  ✓ Correct path
```

**If wrong telemetry appears, test setup is broken:**
```
Test 1: GivenSalesLineExists...  (expects SALESLINE branch)
  DEBUG-TEST-START → GivenSalesLineExists...
  DEBUG-BRANCH-NOSALESLINE → Using Config Header  ✗ WRONG PATH!
```

This catches bugs that assertions cannot—the assertion might still pass if both paths produce the same value.

## BC Event Subscriber Telemetry Pattern

When tests fail because standard BC code isn't behaving as expected, we can't add DEBUG telemetry directly to BC code. Instead, we create temporary event subscribers that emit telemetry from BC's published events.

This pattern applies to **any BC subsystem**—pricing, posting, warehouse, manufacturing, etc. The pricing engine example below is just one application of a universal debugging technique.

### When to Use

- BC subsystem returns unexpected values (pricing engine, posting routines, document handling, etc.)
- Need to understand which BC code paths are executing
- Standard BC behavior is opaque and assertions alone can't diagnose the issue
- Any situation where you need visibility into what standard BC is doing internally

### Finding Relevant BC Events

Use the **bc-w1-reference skill** to find events in the BC subsystem you're debugging:

```powershell
# Find integration events in a specific subsystem
rg -n "IntegrationEvent" "../_aldoc/bc-w1/BaseApp/Source/Base Application/Pricing/"
rg -n "IntegrationEvent" "../_aldoc/bc-w1/BaseApp/Source/Base Application/Sales/"
rg -n "IntegrationEvent" "../_aldoc/bc-w1/BaseApp/Source/Base Application/Purchases/"

# Find events by name pattern
rg -l "OnAfterPost" "../_aldoc/bc-w1/BaseApp/Source/Base Application/"
rg -l "OnBeforeValidate" "../_aldoc/bc-w1/BaseApp/Source/Base Application/"
```

Or use the Task tool with subagent_type=Explore to search the bc-w1 mirror:

```
Task tool:
  subagent_type: Explore
  prompt: "Search the BC W1 source mirror for integration events in [subsystem].
           Find events that fire during [specific operation] that could help debug [issue]."
```

### Implementation Steps

1. **Find relevant BC events** using bc-w1-reference skill (see above)

2. **Create temporary debug subscriber codeunit** in test folder:

```al
codeunit 50XXX "NALICF Debug [Subsystem] Subsc"
{
    Access = Internal;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"[BC Codeunit]", '[EventName]', '', false, false)]
    local procedure OnAfter[Event](var [Params])
    var
        FeatureTelemetry: Codeunit "Feature Telemetry";
    begin
        FeatureTelemetry.LogUsage('DEBUG-BC-[SUBSYSTEM]-[EVENT]', '[Area]',
            StrSubstNo('[Description]: %1', [RelevantValue]));
    end;
}
```

3. **Run tests and analyze telemetry.jsonl** — Correlate BC events with test execution:

```powershell
Select-String -Path .output/TestResults/telemetry.jsonl -Pattern "DEBUG-BC-"
```

4. **Delete the subscriber codeunit after debugging** — It's temporary scaffolding, not production code.

### Example: BC Pricing Engine

This example shows debugging the Price Calculation - V16 codeunit, but the same approach works for any BC subsystem (posting codeunits, document management, inventory, etc.):

```al
codeunit 50105 "NALICF Debug Price Subsc"
{
    Access = Internal;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Price Calculation - V16", 'OnAfterFindLines', '', false, false)]
    local procedure OnAfterFindLines(var PriceListLine: Record "Price List Line"; AmountType: Enum "Price Amount Type"; var IsHandled: Boolean)
    var
        FeatureTelemetry: Codeunit "Feature Telemetry";
    begin
        FeatureTelemetry.LogUsage('DEBUG-BC-PRICING-FINDLINES', 'Pricing',
            StrSubstNo('Found %1 lines, IsHandled=%2', PriceListLine.Count(), IsHandled));
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Price Calculation - V16", 'OnAfterCalcBestAmount', '', false, false)]
    local procedure OnAfterCalcBestAmount(var PriceListLine: Record "Price List Line")
    var
        FeatureTelemetry: Codeunit "Feature Telemetry";
    begin
        FeatureTelemetry.LogUsage('DEBUG-BC-PRICING-BESTAMOUNT', 'Pricing',
            StrSubstNo('BestAmount: UnitPrice=%1, Status=%2', PriceListLine."Unit Price", PriceListLine.Status));
    end;
}
```

This revealed the V16 pricing engine wasn't enabled—leading to the fix:

```al
LibraryPriceCalculation.EnableExtendedPriceCalculation();
LibraryPriceCalculation.SetupDefaultHandler("Price Calculation Handler"::"Business Central (Version 16.0)");
```

### Other Subsystem Examples

The same pattern applies to any BC area:

| Subsystem | Example Events to Subscribe |
|-----------|----------------------------|
| Sales Posting | `OnAfterPostSalesDoc`, `OnBeforePostSalesDoc` in "Sales-Post" |
| Purchase Posting | `OnAfterPostPurchaseDoc`, `OnBeforePostPurchaseDoc` in "Purch.-Post" |
| Inventory | `OnAfterPostItemJnlLine` in "Item Jnl.-Post Line" |
| Warehouse | `OnAfterCreateWhseJnlLine` in "Whse. Jnl.-Register Line" |
| Manufacturing | `OnAfterPostProdOrder` in "Production Order-Post" |

Use bc-w1-reference to discover the specific events available in each subsystem.

### Key Points

- Subscriber codeunits are **temporary**—delete after debugging
- Use `DEBUG-BC-*` prefix to distinguish from app telemetry
- Place in test folder (not app folder) to avoid shipping debug code
- Combine with test-start telemetry to correlate BC events to specific tests
- Use bc-w1-reference skill to find relevant events before creating subscribers
- This pattern works for **any BC subsystem**, not just pricing

## Test Structure Requirements

### Transaction Model Best Practices

**Default: Do NOT specify `[TransactionModel]` on test methods.**

Microsoft's standard BC tests (40,000+ test methods) rely on the **TestRunner's `TestIsolation` property** rather than individual test attributes. Only ~3% of BC standard tests specify `[TransactionModel]`.

**How isolation works in BC:**

| Level | Where Configured | Effect |
|-------|------------------|--------|
| TestRunner | `TestIsolation` property on test runner codeunit | Controls rollback for all tests run by that runner |
| Test Method | `[TransactionModel]` attribute | Overrides TestRunner for that specific test |

**When to use `[TransactionModel]` (exceptions only):**

| Attribute | Use When |
|-----------|----------|
| `[TransactionModel(AutoRollback)]` | Testing pure logic that MUST NOT call `Commit()`. Will ERROR if code under test commits. |
| `[TransactionModel(AutoCommit)]` | Testing code that calls `Commit()` (posting routines, job queue, background sessions). Requires explicit cleanup. |
| `[TransactionModel(None)]` | Simulating real user behavior where each page interaction is a separate transaction. Rare. |

**Why NOT to default to AutoRollback:**
1. Breaks if production code calls `Commit()` (posting, background jobs)
2. Duplicates TestRunner isolation if already configured
3. Inconsistent with Microsoft's own test patterns
4. Limits ability to test realistic business scenarios

### Template Reference

When creating new test codeunits, follow the structure in [NALICFTestTemplate.Codeunit.al](references/NALICFTestTemplate.Codeunit.al).

**Key elements:**
1. Subtype = Test, Access = Internal
2. `FeatureTelemetry` and `IsInitialized` variables
3. Gherkin comments: `[SCENARIO]`, `[GIVEN]`, `[WHEN]`, `[THEN]`
4. `Initialize()` procedure with IsInitialized guard
5. Test-start telemetry as first line after declarations
6. **No `[TransactionModel]` by default** — let TestRunner handle isolation

**New test codeunit setup:**
1. Create file in appropriate folder: `test/src/Workflows/<Feature>/NALICF<Feature>Test.Codeunit.al`
2. Allocate ID using `al-object-id-allocator` skill
3. Only add `[TransactionModel]` if you have a specific reason (see table above)
