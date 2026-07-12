import Testing

@testable import SuttoDomain

// Ported test-for-test from parser.test.ts in the GNOME version of Sutto;
// the shared suite is the compatibility guarantee between the two codebases.
@Suite struct LayoutExpressionParserTests {
    @Suite struct BasicTerms {
        @Test func parsesZero() throws {
            #expect(try LayoutExpressionParser.parse("0") == .zero)
        }

        @Test func parsesIntegerFraction() throws {
            #expect(try LayoutExpressionParser.parse("1/3") == .fraction(numerator: 1, denominator: 3))
        }

        @Test func parsesFractionWithLargerNumbers() throws {
            #expect(try LayoutExpressionParser.parse("5/12") == .fraction(numerator: 5, denominator: 12))
        }

        @Test func rejectsDecimalFraction() {
            #expect(throws: LayoutExpressionParseError.fractionRequiresIntegers("0.5/3")) {
                try LayoutExpressionParser.parse("0.5/3")
            }
        }

        @Test func rejectsDivisionByZero() {
            #expect(throws: LayoutExpressionParseError.divisionByZero("1/0")) {
                try LayoutExpressionParser.parse("1/0")
            }
        }

        @Test func parsesPercentage() throws {
            #expect(try LayoutExpressionParser.parse("50%") == .percentage(0.5))
        }

        @Test func parsesDecimalPercentage() throws {
            #expect(try LayoutExpressionParser.parse("33.33%") == .percentage(0.3333))
        }

        @Test func parsesOneHundredPercent() throws {
            #expect(try LayoutExpressionParser.parse("100%") == .percentage(1.0))
        }

        @Test func parsesPixel() throws {
            #expect(try LayoutExpressionParser.parse("300px") == .pixel(300))
        }

        @Test func parsesDecimalPixel() throws {
            #expect(try LayoutExpressionParser.parse("10.5px") == .pixel(10.5))
        }
    }

    @Suite struct Operations {
        @Test func parsesAddition() throws {
            #expect(
                try LayoutExpressionParser.parse("50% + 10px")
                    == .add(.percentage(0.5), .pixel(10)))
        }

        @Test func parsesSubtraction() throws {
            #expect(
                try LayoutExpressionParser.parse("100% - 300px")
                    == .subtract(.percentage(1.0), .pixel(300)))
        }

        @Test func parsesFractionAddition() throws {
            #expect(
                try LayoutExpressionParser.parse("1/3 + 10px")
                    == .add(.fraction(numerator: 1, denominator: 3), .pixel(10)))
        }

        @Test func parsesComplexExpressionLeftToRight() throws {
            #expect(
                try LayoutExpressionParser.parse("100% - 300px + 10px")
                    == .add(.subtract(.percentage(1.0), .pixel(300)), .pixel(10)))
        }

        @Test func parsesMultipleOperations() throws {
            #expect(
                try LayoutExpressionParser.parse("1/2 - 10px + 5px - 2px")
                    == .subtract(
                        .add(
                            .subtract(.fraction(numerator: 1, denominator: 2), .pixel(10)),
                            .pixel(5)),
                        .pixel(2)))
        }
    }

    @Suite struct WhitespaceHandling {
        @Test func handlesWhitespaceVariations() throws {
            let withSpaces = try LayoutExpressionParser.parse("100% - 300px")
            let withoutSpaces = try LayoutExpressionParser.parse("100%-300px")
            let extraSpaces = try LayoutExpressionParser.parse(" 100%  -  300px ")

            #expect(withoutSpaces == withSpaces)
            #expect(extraSpaces == withSpaces)
        }

        @Test func handlesWhitespaceInComplexExpressions() throws {
            #expect(
                try LayoutExpressionParser.parse("1/3+10px-5px")
                    == (try LayoutExpressionParser.parse("1/3 + 10px - 5px")))
        }
    }

    @Suite struct ErrorCases {
        @Test func throwsOnEmptyString() {
            #expect(throws: LayoutExpressionParseError.emptyExpression) {
                try LayoutExpressionParser.parse("")
            }
        }

        @Test func throwsOnWhitespaceOnly() {
            #expect(throws: LayoutExpressionParseError.emptyExpression) {
                try LayoutExpressionParser.parse("   ")
            }
        }

        @Test func throwsOnInvalidSyntax() {
            #expect(throws: LayoutExpressionParseError.invalidTerm("abc")) {
                try LayoutExpressionParser.parse("abc")
            }
        }

        @Test func throwsOnIncompleteExpression() {
            #expect(throws: LayoutExpressionParseError.incompleteExpression(afterOperator: "-")) {
                try LayoutExpressionParser.parse("100% - ")
            }
        }

        @Test func throwsOnIncompleteExpressionOperatorOnly() {
            #expect(throws: LayoutExpressionParseError.incompleteExpression(afterOperator: "+")) {
                try LayoutExpressionParser.parse("100% +")
            }
        }

        @Test func throwsOnInvalidPercentage() {
            #expect(throws: LayoutExpressionParseError.invalidPercentage("abc%")) {
                try LayoutExpressionParser.parse("abc%")
            }
        }

        @Test func throwsOnInvalidPixel() {
            #expect(throws: LayoutExpressionParseError.invalidPixel("abcpx")) {
                try LayoutExpressionParser.parse("abcpx")
            }
        }

        @Test func throwsOnInvalidFractionFormat() {
            #expect(throws: LayoutExpressionParseError.invalidFraction("1/2/3")) {
                try LayoutExpressionParser.parse("1/2/3")
            }
        }
    }

    @Suite struct EdgeCases {
        @Test func parsesZeroPixel() throws {
            #expect(try LayoutExpressionParser.parse("0px") == .pixel(0))
        }

        @Test func parsesZeroPercentage() throws {
            #expect(try LayoutExpressionParser.parse("0%") == .percentage(0))
        }

        @Test func parsesOneOverOneFraction() throws {
            #expect(try LayoutExpressionParser.parse("1/1") == .fraction(numerator: 1, denominator: 1))
        }
    }
}
