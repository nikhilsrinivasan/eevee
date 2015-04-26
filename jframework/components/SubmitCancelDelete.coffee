###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


J.dc 'SubmitCancelDelete',
    props:
        showSubmit:
            type: $$.bool
            default: true
        showCancel:
            type: React.PropTypes.bool.isRequired
            default: true
        showDelete:
            type: React.PropTypes.bool.isRequired
            default: false
        onSubmit:
            type: React.PropTypes.func
        onCancel:
            type: React.PropTypes.func
        onDelete:
            type: React.PropTypes.func
        style:
            type: React.PropTypes.object
            default: {}


    render: ->
        $$ ('div'),
            style: @prop.style()

            if @prop.showDelete()
                $$ ('LinkButton'),
                    onClick: =>
                        @prop.onDelete()? {}
                    $$ ('span'),
                        style:
                            float: 'right'
                            paddingLeft: 8
                            fontSize: 12
                            color: 'red'
                            opacity: .5
                        ('Delete')

            if @prop.showSubmit()
                $$ ('Button'),
                    style:
                        marginRight: 8
                    onClick: =>
                        @prop.onSubmit()? {}
                    ('Submit')

            if @prop.showCancel()
                $$ ('CancelButton'),
                    onClick: =>
                        @prop.onCancel()? {}