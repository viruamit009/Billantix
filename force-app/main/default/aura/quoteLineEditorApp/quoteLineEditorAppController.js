({
    init: function(component, event, helper) {
        var pageRef = component.get("v.pageReference");
        if (pageRef && pageRef.state && pageRef.state.c__recordId) {
            component.set("v.recordId", pageRef.state.c__recordId);
        }
    }
})
