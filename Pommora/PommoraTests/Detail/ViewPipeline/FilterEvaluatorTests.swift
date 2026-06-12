//
//  FilterEvaluatorTests.swift
//  PommoraTests
//
//  Pure-logic tests for the view-pipeline filter engine. No disk.
//

import Foundation
import Testing

@testable import Pommora

struct FilterEvaluatorTests {
    private func rule(_ id: String, _ op: String, _ value: String? = nil) -> FilterRule {
        FilterRule(propertyID: id, op: op, value: value)
    }

    private func group(_ match: MatchMode, _ rules: FilterRule...) -> FilterGroup {
        FilterGroup(match: match, rules: rules)
    }

    // MARK: - Empty filter is identity

    @Test func emptyRuleSetMatchesEverything() {
        let fm = VPFixture.frontmatter(id: "p1")
        #expect(FilterEvaluator.matches(fm, group: group(.all), schema: []))
    }

    // MARK: - Unknown / absent operator no-ops (rule passes)

    @Test func unknownOperatorIsNoOpPass() {
        let schema = [VPFixture.textDef("prop_x", name: "X")]
        let fm = VPFixture.frontmatter(id: "p1", properties: ["prop_x": .select("hello")])
        // "nonsense" is not a FilterOperator → rule passes regardless of value.
        let g = group(.all, rule("prop_x", "nonsense", "zzz"))
        #expect(FilterEvaluator.matches(fm, group: g, schema: schema))
    }

    @Test func ruleForUnknownPropertyIsNoOpPass() {
        let fm = VPFixture.frontmatter(id: "p1")
        // No schema entry for prop_missing → can't evaluate → passes.
        let g = group(.all, rule("prop_missing", "is", "x"))
        #expect(FilterEvaluator.matches(fm, group: g, schema: []))
    }

    // MARK: - Text operators

    @Test func textContainsIsCaseInsensitive() {
        let schema = [VPFixture.textDef("prop_t", name: "Title")]
        let fm = VPFixture.frontmatter(id: "p1", properties: ["prop_t": .select("Hello World")])
        #expect(FilterEvaluator.matches(fm, group: group(.all, rule("prop_t", "contains", "world")), schema: schema))
        #expect(!FilterEvaluator.matches(fm, group: group(.all, rule("prop_t", "contains", "xyz")), schema: schema))
    }

    @Test func textIsAndIsNot() {
        let schema = [VPFixture.textDef("prop_t", name: "T")]
        let fm = VPFixture.frontmatter(id: "p1", properties: ["prop_t": .select("alpha")])
        #expect(FilterEvaluator.matches(fm, group: group(.all, rule("prop_t", "is", "alpha")), schema: schema))
        #expect(!FilterEvaluator.matches(fm, group: group(.all, rule("prop_t", "is", "beta")), schema: schema))
        #expect(FilterEvaluator.matches(fm, group: group(.all, rule("prop_t", "is_not", "beta")), schema: schema))
    }

    @Test func textIsEmptyAndIsNotEmpty() {
        let schema = [VPFixture.textDef("prop_t", name: "T")]
        let present = VPFixture.frontmatter(id: "p1", properties: ["prop_t": .select("x")])
        let absent = VPFixture.frontmatter(id: "p2")
        #expect(FilterEvaluator.matches(absent, group: group(.all, rule("prop_t", "is_empty")), schema: schema))
        #expect(FilterEvaluator.matches(present, group: group(.all, rule("prop_t", "is_not_empty")), schema: schema))
        #expect(!FilterEvaluator.matches(present, group: group(.all, rule("prop_t", "is_empty")), schema: schema))
    }

    @Test func doesNotContainWhenValueAbsentPasses() {
        let schema = [VPFixture.textDef("prop_t", name: "T")]
        let absent = VPFixture.frontmatter(id: "p1")
        #expect(
            FilterEvaluator.matches(absent, group: group(.all, rule("prop_t", "does_not_contain", "z")), schema: schema)
        )
    }

    // MARK: - Number operators

    @Test func numberGreaterAndLessThan() {
        let schema = [VPFixture.numberDef("prop_n", name: "N")]
        let fm = VPFixture.frontmatter(id: "p1", properties: ["prop_n": .number(5)])
        #expect(FilterEvaluator.matches(fm, group: group(.all, rule("prop_n", "greater_than", "3")), schema: schema))
        #expect(!FilterEvaluator.matches(fm, group: group(.all, rule("prop_n", "greater_than", "9")), schema: schema))
        #expect(FilterEvaluator.matches(fm, group: group(.all, rule("prop_n", "less_than", "9")), schema: schema))
    }

    @Test func numberOperatorOutsideMatrixNoOps() {
        // `contains` is meaningless for number → no-op pass.
        let schema = [VPFixture.numberDef("prop_n", name: "N")]
        let fm = VPFixture.frontmatter(id: "p1", properties: ["prop_n": .number(5)])
        #expect(FilterEvaluator.matches(fm, group: group(.all, rule("prop_n", "contains", "5")), schema: schema))
    }

    // MARK: - Date operators

    @Test func dateOnOrAfterAndOnOrBefore() {
        let schema = [VPFixture.dateDef("prop_d", name: "D")]
        let fm = VPFixture.frontmatter(
            id: "p1", properties: ["prop_d": .datetime(VPFixture.date("2026-06-10T00:00:00Z"))])
        #expect(
            FilterEvaluator.matches(
                fm, group: group(.all, rule("prop_d", "on_or_after", "2026-06-10T00:00:00Z")), schema: schema))
        #expect(
            !FilterEvaluator.matches(
                fm, group: group(.all, rule("prop_d", "on_or_after", "2026-06-11T00:00:00Z")), schema: schema))
        #expect(
            FilterEvaluator.matches(
                fm, group: group(.all, rule("prop_d", "on_or_before", "2026-06-11T00:00:00Z")), schema: schema))
    }

    // MARK: - Checkbox operators

    @Test func checkboxIsAndIsNot() {
        let schema = [VPFixture.checkboxDef("prop_c", name: "C")]
        let on = VPFixture.frontmatter(id: "p1", properties: ["prop_c": .checkbox(true)])
        let off = VPFixture.frontmatter(id: "p2", properties: ["prop_c": .checkbox(false)])
        #expect(FilterEvaluator.matches(on, group: group(.all, rule("prop_c", "is", "true")), schema: schema))
        #expect(FilterEvaluator.matches(off, group: group(.all, rule("prop_c", "is", "false")), schema: schema))
        #expect(FilterEvaluator.matches(on, group: group(.all, rule("prop_c", "is_not", "false")), schema: schema))
    }

    // MARK: - Tier rules (read fm.tier1/2/3, NOT properties)

    @Test func tierRuleReadsTierArrayNotProperties() {
        let fm = VPFixture.frontmatter(id: "p1", tier1: ["ctx_a", "ctx_b"])
        // _tier1 membership: contains ctx_a → passes.
        #expect(FilterEvaluator.matches(fm, group: group(.all, rule("_tier1", "contains", "ctx_a")), schema: []))
        #expect(!FilterEvaluator.matches(fm, group: group(.all, rule("_tier1", "contains", "ctx_z")), schema: []))
    }

    @Test func tierIsEmptyAndIsNotEmpty() {
        let withTier = VPFixture.frontmatter(id: "p1", tier2: ["ctx_x"])
        let noTier = VPFixture.frontmatter(id: "p2")
        #expect(FilterEvaluator.matches(noTier, group: group(.all, rule("_tier2", "is_empty")), schema: []))
        #expect(FilterEvaluator.matches(withTier, group: group(.all, rule("_tier2", "is_not_empty")), schema: []))
    }

    // MARK: - Match modes

    @Test func matchModeAllIsAND() {
        let schema = [VPFixture.numberDef("prop_n", name: "N"), VPFixture.textDef("prop_t", name: "T")]
        let fm = VPFixture.frontmatter(
            id: "p1", properties: ["prop_n": .number(5), "prop_t": .select("x")])
        let pass = group(.all, rule("prop_n", "greater_than", "1"), rule("prop_t", "is", "x"))
        let fail = group(.all, rule("prop_n", "greater_than", "1"), rule("prop_t", "is", "y"))
        #expect(FilterEvaluator.matches(fm, group: pass, schema: schema))
        #expect(!FilterEvaluator.matches(fm, group: fail, schema: schema))
    }

    @Test func matchModeAnyIsOR() {
        let schema = [VPFixture.numberDef("prop_n", name: "N"), VPFixture.textDef("prop_t", name: "T")]
        let fm = VPFixture.frontmatter(
            id: "p1", properties: ["prop_n": .number(5), "prop_t": .select("x")])
        // One rule fails, one passes → ANY passes.
        let g = group(.any, rule("prop_n", "greater_than", "9"), rule("prop_t", "is", "x"))
        #expect(FilterEvaluator.matches(fm, group: g, schema: schema))
        // Both fail → ANY fails.
        let none = group(.any, rule("prop_n", "greater_than", "9"), rule("prop_t", "is", "y"))
        #expect(!FilterEvaluator.matches(fm, group: none, schema: schema))
    }
}
