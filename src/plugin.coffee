_ = require 'lodash'


exports = module.exports = pass = (ast, options) ->
  myOptions = options.overrideActionPlugin
  initializer = ast.initializer
  overrideInitializer = myOptions.initializer
  rules = ast.rules
  overrideRules = myOptions.rules or {}

  if overrideInitializer
    if _.isFunction overrideInitializer
      overrideInitializer = exports.funToString overrideInitializer
      overrideInitializer = "(function(){#{overrideInitializer}})();"
    ast.initializer = {
      type: 'initializer'
      code: overrideInitializer
    }

  return overrideRules ast, options  if _.isFunction overrideRules

  for rule, ruleIndex in rules
    newValue = overrideRules[rule.name]
    newValueIsArray = Array.isArray newValue
    continue  unless newValue?

    ruleName = rule.name
    if rule.expression.type == 'named'
      ruleName += " \"#{rule.name}\""
      rule = rule.expression
    if newValueIsArray and rule.expression.type is 'choice'
      alternatives = rule.expression.alternatives
      if alternatives.length isnt newValue.length
        throw new Error "Rule #{ruleName} mismatch (alternatives #{alternatives.length} != #{newValue.length}"
      for alternative, alternativeIndex in alternatives
        alternatives[alternativeIndex] = exports.overrideAction alternative, newValue[alternativeIndex]
    else if not newValueIsArray
      rule.expression = exports.overrideAction rule.expression, newValue
    else
      throw new Error "Rule #{ruleName} mismatch (needs no alternatives)"
  ast


exports.use = (config, options = {}) ->
  unless options.overrideActionPlugin?
    throw new Error 'Please define overrideActionPlugin as an option to PEGjs'
  stage = config.passes.transform
  stage.unshift pass


exports.funToString = (fun) ->
  fun = fun.toString()
  bodyStarts = fun.indexOf('{') + 1
  bodyEnds = fun.lastIndexOf '}'
  fun.substring bodyStarts, bodyEnds


exports.action$ = () ->
  join = (arr) -> arr.join ''
  recursiveJoin = (value) ->
    if Array.isArray value
      value = value.map recursiveJoin
      value = join value
    value
  recursiveJoin __result


exports.actionIgnore = () ->
  ''


exports.overrideAction = (rule, code) ->
  code = exports.funToString code  if _.isFunction code
  code = exports.action$  if code is '__$__'
  code = exports.actionIgnore  if code is '__ignore__'
  return rule  if code is undefined
  if rule.type isnt 'action'
    rule = {
      type: 'action'
      expression: rule
    }

  rule.code = code
  rule


exports.makeBuildParser = ({grammar, initializer, rules, mixins, PEG}) ->
  mixins ?= []
  _.defaults rules, mixin  for mixin in mixins
  mod = ({startRule, options}) ->
    options ?= {}
    _.assign options, {
      allowedStartRules: [startRule]
      plugins: [exports]
      overrideActionPlugin: {
        initializer
        rules
      }
    }

    parser = PEG.buildParser grammar, options
    if options.output is 'source'
      return """(function(){
      var original = #{parser};
        var fun = original.parse;
        fun.SyntaxError = original.SyntaxError;
        fun.parse = original.parse;
        return fun;
      })()
      """

    # FIXME pegjs should throw an exception if startRule is not defined
    {SyntaxError, parse} = parser
    parser = parse
    parser._parse = parse
    parser.SyntaxError = SyntaxError

    parser.parse = (input, options = {}) ->
      _.defaults options, {
        startRule
      }
      parser._parse input, options
    parser._ = {
      grammar
      options
    }
    parser

  mod._ = {
    grammar
    initializer
    rules
  }

  mod
