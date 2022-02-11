//
//  DDTestCaseRewriter.swift
//  DDTestcaseHelper
//
//  Created by Rostyslav Kobyzskyi on 2/3/22.
//

import Foundation
import SwiftSyntax

public class DDTestCaseRewriter: SyntaxRewriter {

    public func visit(_ url: URL) throws -> Syntax {
        Syntax(visit(try SyntaxParser.parse(source: try String(contentsOf: url))))
    }
    
    public override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        guard !node.isDDTestCase else { return DeclSyntax(node) }
        guard let inheritance = node.inheritanceClause else { return DeclSyntax(node) }
        var node = node
        
        if let xcTestCaseInheritance = inheritance.inheritedTypeCollection.first(where: { $0.typeName.as(SimpleTypeIdentifierSyntax.self)?.name.text == Constants.unitTestClassName
        }) {
            
            node = node.withInheritanceClause(
                inheritance.withInheritedTypeCollection(
                    inheritance.inheritedTypeCollection.replacing(
                        childAt: xcTestCaseInheritance.indexInParent,
                        with: xcTestCaseInheritance.withTypeName(
                            SyntaxFactory.makeTypeIdentifier(
                                Constants.ddUnitTestClassName,
                                trailingTrivia: xcTestCaseInheritance.trailingComma == nil
                                ? .spaces(1)
                                : .zero
                            )
                        )
                    )
                )
            )
        }
        guard node.inheritanceClause!.inheritedTypeCollection.contains(where: { inh in
            inh.typeName.as(SimpleTypeIdentifierSyntax.self)?.name.text == Constants.ddUnitTestClassName
        }) else { return DeclSyntax(node) }
        
        
        let optionalVarsWithExclMark = node.members
            .allVariables()
            .filter(\.isOptionalWithExclMark)
            .compactMap(\.name)
        
        guard !optionalVarsWithExclMark.isEmpty else { return DeclSyntax(node) }
        
        
        if !node.members.allFunctions().contains(where: \.isTearDownOrWithError) {
            node = node.withMembers(node.members.addMember(
                SyntaxFactory.makeMemberDeclListItem(
                    decl: DeclSyntax(SyntaxFactory.makeOverrideFuncDecl(identifier: "tearDown")),
                    semicolon: nil
                )
            ))
        }
        
        
        node.members
            .allFunctions()
            .filter { fn in
                fn.identifier.text == "tearDown" ||
                fn.identifier.text == "tearDownWithError" ||
                fn.identifier.text == "setUp" ||
                fn.identifier.text == "setUpWithError"
            }
            .filter { !$0.hasSuperCall }
            .filter { $0.parent != nil }
            .forEach { fn in
                node = node.withMembers(
                    node.members.withMembers(
                        node.members.members.replacing(
                            childAt: fn.parent!.indexInParent,
                            with: SyntaxFactory.makeMemberDeclListItem(
                                decl: DeclSyntax(fn.superizing),
                                semicolon: nil
                            )
                        )
                    )
                )
            }
        
        node = node.withMembers(
            node.members
                .allFunctions()
                .filter { $0.modifiers != nil }
                .filter { !$0.modifiers!.isClassModifier }
                .first(where: { $0.identifier.text == "tearDown" || $0.identifier.text == "tearDownWithError" })
                .map { fn -> MemberDeclListSyntax? in
                    if let idx = fn.parent?.indexInParent {
                        return node.members.members.replacing(
                            childAt: idx,
                            with: SyntaxFactory.makeMemberDeclListItem(
                                decl: DeclSyntax(fn.nullifying(
                                    vars: .init(optionalVarsWithExclMark))),
                                semicolon: nil
                            )
                        )
                    } else {
                        return .none
                    }
                }
                .map { node.members.withMembers($0) } ??
            node.members
        )
        return DDTestCaseInheritanceRewriter().visit(node)
    }
}

extension FunctionDeclSyntax {
    var isTearDownOrWithError: Bool {
        identifier.text == "tearDown" || identifier.text == "tearDownWithError"
    }
}

func findParent(syntax: Syntax) -> Syntax {
    guard let parent = syntax.parent else { return syntax }
    return findParent(syntax: parent)
}

extension FunctionDeclSyntax {
    var hasSuperCall: Bool {
        body?.statements
            .compactMap({
                $0.item.as(FunctionCallExprSyntax.self) ??
                $0.item.as(TryExprSyntax.self)?.expression.as(FunctionCallExprSyntax.self)
            })
            .contains { fn in
                fn.calledExpression.tokens.contains(where: { $0.tokenKind == .superKeyword }) &&
                fn.calledExpression.tokens.contains(where: { $0.tokenKind == .identifier(self.identifier.text) })
            } ?? false
    }
    
    var superizing: FunctionDeclSyntax {
        let body = body ?? SyntaxFactory.makeCodeBlock(
            leftBrace: SyntaxFactory.makeLeftBraceToken(
                leadingTrivia: .zero, trailingTrivia: .zero),
            statements: SyntaxFactory.makeCodeBlockItemList([]),
            rightBrace: SyntaxFactory.makeRightBraceToken(
                leadingTrivia: .zero, trailingTrivia: .zero)
        )
        return self.withBody(
            body.withStatements(
                body.statements.inserting(
                    SyntaxFactory.makeCodeBlockItem(
                        item: Syntax(
                            signature.throwsOrRethrowsKeyword != nil
                            ? ExprSyntax(SyntaxFactory.makeTryExpr(
                                tryKeyword: SyntaxFactory.makeTryKeyword(
                                    leadingTrivia: .init(pieces: [.newlines(1), .spaces(8)]),
                                    trailingTrivia: .spaces(1)),
                                questionOrExclamationMark: nil,
                                expression: ExprSyntax(SyntaxFactory.makeSuperCallStatement(identifier: identifier.text))
                            ))
                            : ExprSyntax(SyntaxFactory.makeSuperCallStatement(
                                identifier: identifier.text,
                                leadingTrivia: [.newlines(1), .spaces(8)]))
                        ),
                        semicolon: nil,
                        errorTokens: nil
                    ),
                    at: 0)
            )
        )
    }
    
    func nullifying(vars: Set<String>) -> FunctionDeclSyntax {
        guard var body = body else { return self }
        
        body = vars
            .symmetricDifference(Set(
                body.statements
                    .compactMap({ $0.item.as(SequenceExprSyntax.self) })
                    .compactMap(\.nullifiedIdentifier)
            ))
            .map(SyntaxFactory.makeNullifyCodeBlockItemSyntax)
            .reduce(body, { $0.addStatement($1) })
        
        return self.withBody(body)
    }
}

extension SyntaxFactory {
    static func makeOverrideFuncDecl(identifier: String) -> FunctionDeclSyntax {
        SyntaxFactory.makeFunctionDecl(
            attributes: nil,
            modifiers: SyntaxFactory.makeModifierList([
                SyntaxFactory.makeDeclModifier(
                    name: SyntaxFactory.makeIdentifier(
                        "override",
                        leadingTrivia: .init(
                            pieces: [
                            .newlines(2),
                            .spaces(4)
                        ]),
                        trailingTrivia: .spaces(1)),
                    detailLeftParen: nil,
                    detail: nil,
                    detailRightParen: nil)
            ]),
            funcKeyword: SyntaxFactory.makeFuncKeyword(
                leadingTrivia: .zero,
                trailingTrivia: .spaces(1)),
            identifier: SyntaxFactory.makeIdentifier(identifier),
            genericParameterClause: nil,
            signature: makeFunctionSignature(
                input: makeParameterClause(
                    leftParen: SyntaxFactory.makeLeftParenToken(),
                    parameterList: SyntaxFactory.makeFunctionParameterList([]),
                    rightParen: SyntaxFactory.makeRightParenToken(
                        leadingTrivia: .zero,
                        trailingTrivia: .spaces(1))),
                asyncOrReasyncKeyword: nil,
                throwsOrRethrowsKeyword: nil,
                output: nil),
            genericWhereClause: nil,
            body: SyntaxFactory.makeCodeBlock(
                leftBrace: SyntaxFactory.makeLeftBraceToken(),
                statements: SyntaxFactory.makeCodeBlockItemList([]),
                rightBrace: SyntaxFactory.makeRightBraceToken(
                    leadingTrivia: .init(pieces: [.newlines(1), .spaces(4)]),
                    trailingTrivia: .zero)))
    }
}

extension SyntaxFactory {
    static func makeSuperCallStatement(
        identifier: String,
        leadingTrivia: Trivia = [],
        trailingTrivia: Trivia = []
    ) -> FunctionCallExprSyntax {
        SyntaxFactory.makeFunctionCallExpr(
            calledExpression: ExprSyntax(SyntaxFactory.makeMemberAccessExpr(
                base: ExprSyntax(SyntaxFactory.makeSuperRefExpr(
                    superKeyword: SyntaxFactory.makeSuperKeyword(
                        leadingTrivia: leadingTrivia,
                        trailingTrivia: trailingTrivia))),
                dot: SyntaxFactory.makePeriodToken(),
                name: SyntaxFactory.makeIdentifier(identifier),
                declNameArguments: nil)),
            leftParen: SyntaxFactory.makeLeftParenToken(),
            argumentList: SyntaxFactory.makeTupleExprElementList([]),
            rightParen: SyntaxFactory.makeRightParenToken(),
            trailingClosure: nil,
            additionalTrailingClosures: nil
        )
    }
}

extension SyntaxFactory {
    static func makeNullifyCodeBlockItemSyntax(_ identifier: String) -> CodeBlockItemSyntax {
        SyntaxFactory.makeCodeBlockItem(
            item: Syntax(
                SyntaxFactory.makeExprList([
                    ExprSyntax(
                        SyntaxFactory.makeIdentifierExpr(
                            identifier: SyntaxFactory.makeIdentifier(
                                identifier,
                                leadingTrivia: .init(pieces: [
                                    .newlines(1),
                                    .spaces(8)
                                ]),
                                trailingTrivia: .zero
                            ),
                            declNameArguments: nil
                        )
                    ),
                    ExprSyntax(SyntaxFactory.makeAssignmentExpr(
                        assignToken: SyntaxFactory.makeEqualToken(
                            leadingTrivia: .spaces(1),
                            trailingTrivia: .spaces(1)))),
                    ExprSyntax(SyntaxFactory.makeAssignmentExpr(
                        assignToken: SyntaxFactory.makeNilKeyword(
                            leadingTrivia: .zero,
                            trailingTrivia: .zero))),
                ])
            ),
            semicolon: nil,
            errorTokens: nil
        )
    }
}

extension MemberDeclBlockSyntax {
    fileprivate func allVariables() -> [VariableDeclSyntax] {
        members.map(\.decl).compactMap { $0.as(VariableDeclSyntax.self) }.filter(\.isVariable)
    }
}

extension MemberDeclBlockSyntax {
    fileprivate func allFunctions() -> [FunctionDeclSyntax] {
        members.map(\.decl).compactMap { $0.as(FunctionDeclSyntax.self) }
    }
}

extension ModifierListSyntax {
    fileprivate var isClassModifier: Bool {
        tokens.contains { $0.text == "class" }
    }
}

extension VariableDeclSyntax {
    fileprivate var isVariable: Bool { letOrVarKeyword.text == "var" }
}

extension VariableDeclSyntax {
    // TODO: check multiple bindings case
    fileprivate var name: String? {
        bindings.first?.name
    }
    
    // TODO: check multiple bindings case
    fileprivate var isOptionalWithExclMark: Bool {
        bindings.first?.isOptionalWithExclMark ?? false
    }
}

extension PatternBindingSyntax {
    fileprivate var name: String? {
        pattern.firstToken?.text
    }
    fileprivate var isOptionalWithExclMark: Bool {
        typeAnnotation?.tokens.contains(where: { $0.tokenKind == .exclamationMark }) ?? false
    }
}

extension SequenceExprSyntax {
    fileprivate var nullifiedIdentifier: String? {
        guard
            elements.tokens.contains(where: tokenKindPredicate(.equal)),
            elements.tokens.contains(where: tokenKindPredicate(.nilKeyword)),
            elements.contains(where: { $0.is(IdentifierExprSyntax.self) })
        else {
            return .none
        }
        
        return elements.tokens.compactMap { token -> String? in
            if case .identifier(let name) = token.tokenKind {
                return name
            } else {
                return .none
            }
        }
        .first
    }
}

let tokenKindPredicate: (TokenKind) -> (TokenSyntax) -> Bool = { kind in
    { $0.tokenKind == kind }
}

public class DDTestCaseInheritanceRewriter: SyntaxRewriter {
    public override func visit(_ node: InheritedTypeListSyntax) -> Syntax {
        guard let idx = node.tokens.enumerated().first(where: { $0.element.isUnitTest })?.offset else {
            return Syntax(node)
        }
        
        return Syntax(node.replacing(childAt: idx, with: SyntaxFactory.makeInheritedType(
            typeName: SyntaxFactory.makeTypeIdentifier(
                Constants.ddUnitTestClassName,
                leadingTrivia: idx == 0 ? .spaces(1) : .zero
            ),
            trailingComma: node.count > 1
                ? SyntaxFactory.makeCommaToken(leadingTrivia: .zero, trailingTrivia: .spaces(1))
                : .none
        )))
        
    }
}

enum Constants {
    static let unitTestClassName = "XCTestCase"
    static let ddUnitTestClassName = "DDTestCase"
}

extension ClassDeclSyntax {
    var isDDTestCase: Bool {
        identifier.text == Constants.ddUnitTestClassName
    }
}

extension TokenSyntax {
    var isUnitTest: Bool {
        text == Constants.unitTestClassName
    }
    
    var isDDUnitTest: Bool {
        text == Constants.ddUnitTestClassName
    }
}


