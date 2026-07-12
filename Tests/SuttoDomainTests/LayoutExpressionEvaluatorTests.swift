import Testing

@testable import SuttoDomain

/// `MINIATURE_DISPLAY_WIDTH` constant in the GNOME version.
private let displayWidth: Double = 300

private func evaluate(
    _ expression: String,
    containerSize: Double,
    screenSize: Double? = nil
) throws -> Double {
    let parsed = try LayoutExpressionParser.parse(expression)
    return LayoutExpressionEvaluator.evaluate(
        parsed, containerSize: containerSize, screenSize: screenSize)
}

// Ported test-for-test from evaluator.test.ts in the GNOME version of Sutto;
// the shared suite is the compatibility guarantee between the two codebases.
@Suite struct LayoutExpressionEvaluatorTests {
    @Suite struct BasicUnits {
        @Test func evaluatesZero() throws {
            #expect(try evaluate("0", containerSize: displayWidth) == 0)
        }

        @Test func evaluatesFraction() throws {
            #expect(try evaluate("1/3", containerSize: displayWidth) == 100)
        }

        @Test func evaluatesFractionOneHalf() throws {
            #expect(try evaluate("1/2", containerSize: displayWidth) == 150)
        }

        @Test func evaluatesFractionTwoThirds() throws {
            #expect(try evaluate("2/3", containerSize: displayWidth) == 200)
        }

        @Test func evaluatesPercentage() throws {
            #expect(try evaluate("50%", containerSize: displayWidth) == 150)
        }

        @Test func evaluatesOneHundredPercent() throws {
            #expect(try evaluate("100%", containerSize: displayWidth) == 300)
        }

        @Test func evaluatesTwentyFivePercent() throws {
            #expect(try evaluate("25%", containerSize: displayWidth) == 75)
        }

        @Test func evaluatesPixel() throws {
            #expect(try evaluate("50px", containerSize: displayWidth) == 50)
        }

        @Test func evaluatesZeroPixel() throws {
            #expect(try evaluate("0px", containerSize: displayWidth) == 0)
        }
    }

    @Suite struct CompositeExpressions {
        @Test func evaluatesAdditionPercentagePlusPixel() throws {
            #expect(try evaluate("50% + 10px", containerSize: displayWidth) == 160)
        }

        @Test func evaluatesSubtractionPercentageMinusPixel() throws {
            #expect(try evaluate("100% - 50px", containerSize: displayWidth) == 250)
        }

        @Test func evaluatesFractionPlusPixel() throws {
            #expect(try evaluate("1/3 + 10px", containerSize: displayWidth) == 110)
        }

        @Test func evaluatesFractionMinusPixel() throws {
            #expect(try evaluate("1/3 - 20px", containerSize: displayWidth) == 80)
        }

        @Test func evaluatesComplexExpression() throws {
            #expect(try evaluate("100% - 50px + 10px", containerSize: displayWidth) == 260)
        }

        @Test func evaluatesMultipleSubtractions() throws {
            #expect(try evaluate("100% - 20px - 10px", containerSize: displayWidth) == 270)
        }

        @Test func evaluatesPixelPlusPixel() throws {
            #expect(try evaluate("100px + 50px", containerSize: displayWidth) == 150)
        }

        @Test func evaluatesPercentagePlusPercentage() throws {
            #expect(try evaluate("25% + 25%", containerSize: displayWidth) == 150)
        }
    }

    @Suite struct RealWorldScenarios {
        @Test func evaluatesCenteredLayoutXPosition() throws {
            // x: '50% - 150px' for 300px wide window
            // = 150 - 150 = 0 (left edge when centered on 300px display)
            #expect(try evaluate("50% - 150px", containerSize: displayWidth) == 0)
        }

        @Test func evaluatesRightAlignedPanel() throws {
            // x: '100% - 75px' for 75px wide panel
            // = 300 - 75 = 225
            #expect(try evaluate("100% - 75px", containerSize: displayWidth) == 225)
        }

        @Test func evaluatesPaddedLayout() throws {
            // width: '100% - 20px' with 10px padding on each side
            // = 300 - 20 = 280
            #expect(try evaluate("100% - 20px", containerSize: displayWidth) == 280)
        }

        @Test func evaluatesPaddedThird() throws {
            // width: '1/3 - 20px' (one third with 10px padding each side)
            // = 100 - 20 = 80
            #expect(try evaluate("1/3 - 20px", containerSize: displayWidth) == 80)
        }

        @Test func evaluatesCenteredThirdOffset() throws {
            // x: '1/3 + 10px' (start of second third with 10px offset)
            // = 100 + 10 = 110
            #expect(try evaluate("1/3 + 10px", containerSize: displayWidth) == 110)
        }
    }

    @Suite struct Rounding {
        @Test func roundsToNearestInteger() throws {
            // 33.33% of 300 = 99.99 → 100
            #expect(try evaluate("33.33%", containerSize: displayWidth) == 100)
        }

        @Test func roundsFractionResult() throws {
            // 1/3 of 301 = 100.333... → 100
            #expect(try evaluate("1/3", containerSize: 301) == 100)
        }

        @Test func roundsDownWhenCloserToLowerInteger() throws {
            // 1/3 of 299 = 99.666... → 100
            #expect(try evaluate("1/3", containerSize: 299) == 100)
        }

        @Test func roundsComplexExpression() throws {
            // 33.33% - 0.5px = 99.99 - 0.5 = 99.49 → 99
            #expect(try evaluate("33.33% - 0.5px", containerSize: displayWidth) == 99)
        }
    }

    @Suite struct DifferentContainerSizes {
        @Test func evaluatesFor1920pxScreenWidth() throws {
            #expect(try evaluate("1/3", containerSize: 1920) == 640)
        }

        @Test func evaluatesFor1080pxScreenHeight() throws {
            #expect(try evaluate("50%", containerSize: 1080) == 540)
        }

        @Test func evaluatesComplexForLargeScreen() throws {
            // 100% - 300px for 1920px container
            #expect(try evaluate("100% - 300px", containerSize: 1920) == 1620)
        }

        @Test func evaluatesForSmallContainer() throws {
            // 1/2 of 100px = 50px
            #expect(try evaluate("1/2", containerSize: 100) == 50)
        }
    }

    @Suite struct EdgeCases {
        @Test func evaluatesZeroPercentToZero() throws {
            #expect(try evaluate("0%", containerSize: displayWidth) == 0)
        }

        @Test func evaluatesOneOverOneToContainerSize() throws {
            #expect(try evaluate("1/1", containerSize: displayWidth) == 300)
        }

        @Test func handlesZeroContainerSize() throws {
            #expect(try evaluate("50%", containerSize: 0) == 0)
        }

        @Test func handlesVeryLargeNumbers() throws {
            #expect(try evaluate("10000px", containerSize: displayWidth) == 10000)
        }
    }

    @Suite struct PixelScalingForMiniatureDisplay {
        @Test func scalesDownPixelValuesForMiniatureDisplay() throws {
            // 100px on 1920px screen → scaled down to 300px miniature
            // 100 * (300 / 1920) = 15.625 → 16
            #expect(try evaluate("100px", containerSize: 300, screenSize: 1920) == 16)
        }

        @Test func doesNotScaleWhenScreenSizeIsNotProvided() throws {
            // Actual window positioning: use pixel values as-is
            #expect(try evaluate("100px", containerSize: 1920) == 100)
        }

        @Test func scalesInCompositeExpressions() throws {
            // 100% - 100px on miniature
            // 300 - (100 * 300/1920) = 300 - 15.625 = 284.375 → 284
            #expect(try evaluate("100% - 100px", containerSize: 300, screenSize: 1920) == 284)
        }

        @Test func doesNotAffectRelativeValues() throws {
            // Percentages and fractions are not affected by screenSize
            #expect(try evaluate("50%", containerSize: 300, screenSize: 1920) == 150)
            #expect(try evaluate("1/3", containerSize: 300, screenSize: 1920) == 100)
        }
    }
}
