import Foundation

/// An error produced while parsing a layout expression string.
///
/// Each case corresponds to one error condition of the GNOME implementation;
/// ``description`` reproduces its message text verbatim.
public enum LayoutExpressionParseError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The input was empty or contained only whitespace.
    case emptyExpression

    /// An operator had no operand after it, e.g. `100% -`.
    case incompleteExpression(afterOperator: String)

    /// A token in operator position was neither `+` nor `-`.
    case invalidOperator(String)

    /// A fraction did not have exactly one `/`, e.g. `1/2/3`.
    case invalidFraction(String)

    /// A fraction had a non-integer numerator or denominator, e.g. `0.5/3`.
    case fractionRequiresIntegers(String)

    /// A fraction had a zero denominator, e.g. `1/0`.
    case divisionByZero(String)

    /// A `%` token did not start with a number, e.g. `abc%`.
    case invalidPercentage(String)

    /// A `px` token did not start with a number, e.g. `abcpx`.
    case invalidPixel(String)

    /// A token matched none of the known unit forms, e.g. `abc`.
    case invalidTerm(String)

    public var description: String {
        switch self {
        case .emptyExpression:
            "Empty expression"
        case .incompleteExpression(let afterOperator):
            "Incomplete expression: missing operand after '\(afterOperator)'"
        case .invalidOperator(let token):
            "Invalid operator: '\(token)'"
        case .invalidFraction(let token):
            "Invalid fraction: '\(token)'"
        case .fractionRequiresIntegers(let token):
            "Fractions must use integers: '\(token)'"
        case .divisionByZero(let token):
            "Division by zero in fraction: '\(token)'"
        case .invalidPercentage(let token):
            "Invalid percentage: '\(token)'"
        case .invalidPixel(let token):
            "Invalid pixel value: '\(token)'"
        case .invalidTerm(let token):
            "Invalid term: '\(token)'"
        }
    }
}

/// Parses layout expression strings into ``LayoutExpression`` trees.
///
/// Grammar (identical to the GNOME implementation):
///
/// ```
/// expression := term (operator term)*
/// operator   := '+' | '-'
/// term       := fraction | percentage | pixel | zero
/// fraction   := integer '/' integer
/// percentage := number '%'
/// pixel      := number 'px'
/// zero       := '0'
/// ```
///
/// Operators associate left-to-right and whitespace around them is optional.
public enum LayoutExpressionParser {
    /// Parses an expression string to an AST.
    ///
    /// - Parameter expression: An expression string
    ///   (e.g. `"1/3"`, `"50%"`, `"100% - 20px"`).
    /// - Returns: The parsed expression AST.
    /// - Throws: ``LayoutExpressionParseError`` if the expression is invalid.
    public static func parse(_ expression: String) throws(LayoutExpressionParseError) -> LayoutExpression {
        let tokens = tokenize(expression)

        guard let firstToken = tokens.first else {
            throw LayoutExpressionParseError.emptyExpression
        }

        // Parse the first term, then fold the remaining operator-term pairs
        // left-to-right.
        var result = try parseTerm(firstToken)

        var index = 1
        while index < tokens.count {
            let operatorToken = tokens[index]

            guard index + 1 < tokens.count else {
                throw LayoutExpressionParseError.incompleteExpression(afterOperator: operatorToken)
            }

            let right = try parseTerm(tokens[index + 1])

            switch operatorToken {
            case "+":
                result = .add(result, right)
            case "-":
                result = .subtract(result, right)
            default:
                throw LayoutExpressionParseError.invalidOperator(operatorToken)
            }

            index += 2
        }

        return result
    }

    /// Tokenizes an expression into alternating value and operator tokens.
    ///
    /// A `+` or `-` that appears while the current token is still empty is
    /// treated as the sign of the upcoming number rather than an operator,
    /// mirroring the GNOME tokenizer.
    private static func tokenize(_ expression: String) -> [String] {
        let normalized = expression.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return []
        }

        var tokens: [String] = []
        var currentToken = ""

        for character in normalized {
            if character == "+" || character == "-" {
                let trimmed = currentToken.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    tokens.append(trimmed)
                    tokens.append(String(character))
                    currentToken = ""
                } else {
                    // Possibly the sign of a negative number.
                    currentToken.append(character)
                }
            } else if character == " " {
                // Spaces between tokens are dropped (only the plain space
                // character, matching the GNOME implementation).
            } else {
                currentToken.append(character)
            }
        }

        let trimmed = currentToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            tokens.append(trimmed)
        }

        return tokens
    }

    /// Parses a single term (fraction, percentage, pixel, or zero).
    private static func parseTerm(_ token: String) throws(LayoutExpressionParseError) -> LayoutExpression {
        // Zero
        if token == "0" {
            return .zero
        }

        // Fraction (e.g. "1/3")
        if token.contains("/") {
            let parts = token.components(separatedBy: "/")
            guard parts.count == 2 else {
                throw LayoutExpressionParseError.invalidFraction(token)
            }

            // Only integer fractions are allowed. Unparsable parts also land
            // here, matching the GNOME implementation, where NaN fails the
            // integer check first.
            guard
                let numerator = integer(parsedFrom: parts[0]),
                let denominator = integer(parsedFrom: parts[1])
            else {
                throw LayoutExpressionParseError.fractionRequiresIntegers(token)
            }

            guard denominator != 0 else {
                throw LayoutExpressionParseError.divisionByZero(token)
            }

            return .fraction(numerator: numerator, denominator: denominator)
        }

        // Percentage (e.g. "50%")
        if token.hasSuffix("%") {
            guard let value = leadingDouble(in: String(token.dropLast())) else {
                throw LayoutExpressionParseError.invalidPercentage(token)
            }

            // Convert to the 0-1 range.
            return .percentage(value / 100)
        }

        // Pixel (e.g. "100px")
        if token.hasSuffix("px") {
            guard let value = leadingDouble(in: String(token.dropLast(2))) else {
                throw LayoutExpressionParseError.invalidPixel(token)
            }

            return .pixel(value)
        }

        // Invalid token
        throw LayoutExpressionParseError.invalidTerm(token)
    }

    /// Parses a leading number and returns it only when it is an integer,
    /// like `Number.isInteger(Number.parseFloat(string))` in the GNOME
    /// implementation.
    private static func integer(parsedFrom string: String) -> Int? {
        guard
            let value = leadingDouble(in: string),
            value.truncatingRemainder(dividingBy: 1) == 0,
            let integer = Int(exactly: value)
        else {
            return nil
        }
        return integer
    }

    /// Parses a leading decimal number the way JavaScript's `parseFloat`
    /// does: an optional sign, digits with an optional decimal point, and an
    /// optional exponent; any trailing characters are ignored. Returns `nil`
    /// when the string does not start with a number (where `parseFloat`
    /// returns NaN).
    private static func leadingDouble(in string: String) -> Double? {
        var remainder = Substring(string)

        var sign = ""
        if let first = remainder.first, first == "+" || first == "-" {
            sign = String(first)
            remainder = remainder.dropFirst()
        }

        let integerDigits = takeDigits(from: &remainder)

        var fractionDigits = ""
        if remainder.first == "." {
            remainder = remainder.dropFirst()
            fractionDigits = takeDigits(from: &remainder)
        }

        guard !integerDigits.isEmpty || !fractionDigits.isEmpty else {
            return nil
        }

        var exponent = ""
        if let marker = remainder.first, marker == "e" || marker == "E" {
            var lookahead = remainder.dropFirst()
            var exponentSign = ""
            if let first = lookahead.first, first == "+" || first == "-" {
                exponentSign = String(first)
                lookahead = lookahead.dropFirst()
            }
            let exponentDigits = takeDigits(from: &lookahead)
            if !exponentDigits.isEmpty {
                exponent = "e" + exponentSign + exponentDigits
            }
        }

        var literal = sign + (integerDigits.isEmpty ? "0" : integerDigits)
        if !fractionDigits.isEmpty {
            literal += "." + fractionDigits
        }
        literal += exponent

        return Double(literal)
    }

    /// Consumes and returns the leading run of ASCII digits.
    private static func takeDigits(from remainder: inout Substring) -> String {
        var digits = ""
        while let character = remainder.first, character >= "0", character <= "9" {
            digits.append(character)
            remainder = remainder.dropFirst()
        }
        return digits
    }
}
