###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


class J.AutoDict extends J.Dict
    constructor: (tag, keysFunc, valueFunc, options) ->
        ###
            Overloads
            (1) J.AutoDict [tag], keysFunc, valueFunc, [options]
            (2) J.AutoDict [tag], keysList, valueFunc, [options]
            (3) J.AutoDict [tag], fieldSpecs, [options]

            Options:
                creator
                withFieldFuncs
                fineGrained
                filterFunc
                    Pretend like the only keys are ones whose corresponding
                    value passes filterFunc
        ###

        unless @ instanceof J.AutoDict
            return new J.AutoDict tag, keysFunc, valueFunc, options

        # Reshuffle arguments to make overloads work. We can just
        # convert everything to (tag, keysFunc, valueFunc, onChange).

        if (
            _.isFunction(tag) or
            _.isArray(tag) or tag instanceof J.List or
            (
                (J.util.isPlainObject(tag) or tag instanceof J.Dict) and
                (not keysFunc? or _.isFunction(keysFunc)) and not valueFunc?
            )
        )
            # tag argument not provided
            options = valueFunc
            valueFunc = keysFunc
            keysFunc = tag
            tag = undefined

        if _.isArray(keysFunc) or keysFunc instanceof J.List
            # Overload (2) -> (1)
            # Passing an array seems like good evidence that
            # the creator might want to call a fieldFunc.
            withFieldFuncs = _.isArray keysFunc
            @_keysArr = J.List.unwrap keysFunc
            keysFunc = => @_keysArr

        else if J.util.isPlainObject(keysFunc) or keysFunc instanceof J.Dict
            # Overload (3) -> (1)
            @_fieldSpecs = _.clone J.Dict.unwrap keysFunc
            @_setupGetterSetter key for key in @_fieldSpecs
            options = valueFunc
            keysFunc = => _.keys @_fieldSpecs
            valueFunc = (key) =>
                v = @_fieldSpecs[key]
                if _.isFunction v then v(key) else v
            withFieldFuncs = true

        else
            # Overload (1)
            withFieldFuncs = false


        unless _.isFunction(keysFunc) and _.isFunction(valueFunc)
            throw new Meteor.Error "AutoDict must be constructed with
                keysFunc and valueFunc"

        super {},
            creator: Tracker.currentComputation
            onChange: options?.onChange
            tag: tag
            withFieldFuncs: withFieldFuncs
            fineGrained: options?.fineGrained

        delete @_keysDep

        @keysFunc = keysFunc
        @valueFunc = valueFunc
        @filterFunc =
            if options?.filter is true
                (value) => true
            else options?.filter ? null

        @_keysVar = J.AutoVar(
            (
                autoDict: @
                tag: "#{@toString()} keysVar"
            )

            =>
                keys = @keysFunc.apply null

                unless _.isArray(keys) or keys instanceof J.List
                    throw new Meteor.Error "AutoDict.keysFunc must return a List
                        or array. Got #{J.util.stringify keys}"

                keysArr = J.List.unwrap(keys)

                unless _.all (_.isString(key) for key in keysArr)
                    throw new Meteor.Error "AutoDict keys must all be type string.
                        Got #{J.util.stringify keys}"
                if _.size(J.util.makeSet keysArr) < keys.length
                    throw new Meteor.Error "AutoDict keys must be unique."

                # Side effects during AutoVar recompute functions are usually not okay.
                # We just need the framework to do it in this one place.
                keysDiff = J.util.diffStrings(
                    Tracker.nonreactive => J.Dict::getKeys.call @
                    keysArr
                )
                @_delete key for key in keysDiff.deleted
                @_initField key, J.makeValueNotReadyObject() for key in keysDiff.added

                keysArr

            if @onChange? then true else null

            creator: @creator
            wrap: false
        )

        if @_keysArr? and @withFieldFuncs
            @_setupGetterSetter key for key in @_keysArr
        else if @_fieldSpecs?
            J.assert @withFieldFuncs
            @_setupGetterSetter key for key of @_fieldSpecs

        @_hasKeyDeps = {} # realOrImaginedKey: Dependency


    _delete: (key) ->
        fieldAutoVar = @_fields[key]
        if fieldAutoVar?
            lastValue = fieldAutoVar._value
            if lastValue is undefined or lastValue instanceof J.VALUE_NOT_READY
                lastValue = fieldAutoVar._previousReadyValue
        else
            lastValue = undefined
        if lastValue isnt undefined and @onChange?
            Tracker.afterFlush =>
                if @isActive()
                    @onChange.call @, key, lastValue, undefined

        fieldAutoVar?.stop()
        delete @[key]
        delete @_fields[key]

        if @_hasKeyDeps[key]?
            @_hasKeyDeps[key].changed()
            delete @_hasKeyDeps[key]


    _get: (key, force) ->
        hasKey = @hasKey key
        return undefined if hasKey is undefined

        if hasKey
            if @_fields[key] is null then @_initFieldAutoVar key
            @_fields[key].get()
        else
            if force
                throw new Meteor.Error "#{@constructor.name} missing key #{J.util.stringify key}"
            else
                undefined


    _initField: (key) ->
        if @withFieldFuncs then @_setupGetterSetter key

        if @_hasKeyDeps[key]?
            @_hasKeyDeps[key].changed()
            delete @_hasKeyDeps[key]

        if @onChange
            @_initFieldAutoVar key
        else
            # Save ~1kb of memory until the field is
            # actually needed.
            @_fields[key] = null


    _initFieldAutoVar: (key) ->
        @_fields[key] = J.AutoVar(
            (
                autoDict: @
                fieldKey: key
                tag: "#{@toString()}._fields[#{J.util.stringify key}]"
            )

            =>
                if not @hasKey key, false
                    # This field has just been deleted
                    return J.makeValueNotReadyObject()

                @valueFunc.call null, key, @

            if _.isFunction @onChange
                @onChange.bind @, key
            else
                @onChange

            creator: @creator
        )


    clear: ->
        throw new Meteor.Error "There is no AutoDict.clear"


    clone: ->
        throw new Meteor.Error "There is no AutoDict.clone.
            You should be able to either use the same AutoDict
            or else call snapshot()."

    delete: ->
        throw new Meteor.Error "There is no AutoDict.delete"


    getFields: (keys = @getKeys()) ->
        if keys is undefined
            undefined
        else
            super keys


    getKeys: ->
        if @filterFunc?
            @_keysVar.get().filter (key) =>
                if @_fields[key] is null then @_initFieldAutoVar key
                value = @_fields[key].tryGet()
                value isnt undefined and @filterFunc value
        else
            @_keysVar.get()


    hasKey: (key, _filtered = true) ->
        if @_keysVar._value is undefined or @_keysVar._invalidAncestors.length
            # This might have a special @_replaceKeys side effect
            # which then makes the logic in super work
            keysArr = Tracker.nonreactive => @_keysVar.tryGet()
            return undefined if keysArr is undefined

        if Tracker.active
            @_hasKeyDeps[key] ?= new Tracker.Dependency @creator
            @_hasKeyDeps[key].depend()

        if _filtered and @filterFunc?
            key in @getKeys()
        else
            key of @_fields


    isActive: ->
        not @_keysVar?.stopped


    isReady: (key) ->
        if @hasKey(key, false)
            if @_fields[key] is null then @_initFieldAutoVar key
            @_fields[key].tryGet() isnt undefined
        else
            true


    replaceKeys: ->
        throw new Meteor.Error "There is no AutoDict.replaceKeys; use AutoDict.replaceKeysFunc"


    set: ->
        throw new Meteor.Error "There is no AutoDict.set; use AutoDict.valueFunc"


    setDebug: (@debug) ->


    setOrAdd: ->
        throw new Meteor.Error "There is no AutoDict.setOrAdd; use AutoDict.keysFunc and AutoDict.valueFunc"


    snapshot: ->
        keys = Tracker.nonreactive => J.tryGet => @getKeys()
        if keys is undefined
            undefined
        else
            J.Dict Tracker.nonreactive => @getFields()


    stop: ->
        fieldVar?.stop() for key, fieldVar of @_fields
        @_keysVar.stop()


    toString: ->
        s = "AutoDict[#{@_id}](#{J.util.stringifyTag @tag ? ''})"
        if not @isActive() then s += " (inactive)"
        s