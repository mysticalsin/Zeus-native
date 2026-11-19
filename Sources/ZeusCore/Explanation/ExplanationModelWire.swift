import Foundation

/// Closed JSON shape of every slice S3 operation. Unknown, duplicate and missing keys are
/// rejected before Codable runs, exactly like the version-1 operations.
extension ExplanationWire {
    static func modelOperationSchema(_ name: String, _ value: ExplanationJSONValue) throws {
        switch name {
        case "part":
            let op = try object(value, required: ["op", "part"])
            try partSchema(op["part"]!)
        case "path":
            let op = try object(value, required: ["op", "path"])
            let path = try object(op["path"]!, required: ["id", "points"])
            for point in try array(path["points"]!, maximum: ExplanationModelLimits.pathPoints) { try vectorSchema(point) }
        case "flow":
            let op = try object(value, required: ["op", "flow"])
            _ = try object(op["flow"]!, required: ["id", "pathID", "speed"],
                           optional: ["direction", "count", "color", "active", "markerSize"])
        case "callout":
            let op = try object(value, required: ["op", "callout"])
            let callout = try object(op["callout"]!, required: ["id", "text"], optional: ["partID", "anchor", "visible"])
            if let anchor = callout["anchor"] { try vectorSchema(anchor) }
        case "view":
            _ = try object(value, required: ["op"], optional: ["preset", "orbit", "zoom"])
        case "cutaway":
            let op = try object(value, required: ["op", "expectedRevision", "style", "partIDs"], optional: ["opacity"])
            _ = try array(op["partIDs"]!, maximum: 24)
        case "model":
            _ = try object(value, required: ["op"], optional: ["caption", "animationRate"])
        case "edit":
            let op = try object(value, required: ["op", "id", "expectedRevision", "change"])
            let change = try object(op["change"]!, required: [],
                                    optional: ["opacity", "visible", "color", "metalness", "roughness", "position",
                                               "rotation", "scale", "spin", "speed", "direction", "active", "text"])
            for key in ["position", "rotation", "scale"] { if let vector = change[key] { try vectorSchema(vector) } }
        default:
            throw ExplanationFailure.invalid("unknown operation")
        }
    }

    private static func partSchema(_ value: ExplanationJSONValue) throws {
        let part = try object(value, required: ["id", "kind", "accessibleDescription"],
                              optional: ["parentID", "recipe", "size", "radius", "depth", "transform", "material",
                                         "shell", "repeat", "spin", "visible"])
        if let size = part["size"] { try vectorSchema(size) }
        if let transform = part["transform"] {
            let fields = try object(transform, required: ["position", "rotation", "scale"])
            for vector in fields.values { try vectorSchema(vector) }
        }
        if let material = part["material"] {
            _ = try object(material, required: [], optional: ["color", "metalness", "roughness", "opacity"])
        }
        if let repeats = part["repeat"] {
            let fields = try object(repeats, required: ["count", "offset"])
            try vectorSchema(fields["offset"]!)
        }
        if let spin = part["spin"] { _ = try object(spin, required: ["radiansPerSecond"], optional: ["axis"]) }
    }
}

/// Concise model-facing description of the 3D operations. It carries no scene data.
public enum ExplanationModelPrompt {
    public static let instructions = """
    For a physical mechanism (an engine, a drivetrain, a machine) prefer a 3D scene to a flat diagram.
    Parts: {"op":"part","part":{id,kind,accessibleDescription,...}}. kind group, box(size), cylinder(radius,depth),
    sphere(radius) or recipe with "recipe" batteryPack, inverterBox, motor, reductionGear, halfShafts, wheel or carShell.
    Use recipes for a car drivetrain instead of rebuilding it from boxes. Recipe frame: +x forward, +y up, +z right,
    metres. Optional: parentID (a group), transform, material{color,metalness,roughness,opacity}, shell:true (a part a
    cutaway may hide), repeat{count,offset} for copies, spin{radiansPerSecond,axis} on recipe parts, visible.
    Flow: {"op":"path","path":{id,points}} then {"op":"flow","flow":{id,pathID,speed,direction,count,color,active}};
    direction forward or reverse follows the path's point order in world space. Labels: {"op":"callout","callout":
    {id,text,partID,anchor}}, text under 60 characters. Create parts in the beat whose speech introduces them.
    Follow-ups edit the SAME scene by id and never create a second copy: {"op":"edit","id":partOrFlowID,
    "expectedRevision":<this event's baseRevision>,"change":{opacity,visible,color,metalness,roughness,position,rotation,
    scale,spin,speed,direction,active,text}}; {"op":"cutaway","expectedRevision":N,"style":"hide|transparent|none",
    "partIDs":[shell ids],"opacity":0.15}; {"op":"view","preset":"overview|front|rear|side|top|inside","orbit":degrees,
    "zoom":factor}; {"op":"model","caption":text,"animationRate":0.05..4}. A missing id or a stale expectedRevision
    rejects the whole turn. Motion runs from spin and flow on the app clock, so never animate a wheel by repeated
    rotation. Label a generic demo "generic, explanatory animation, not an engineering simulation".
    """
}
