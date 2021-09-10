import basetypes, math, aabb, algorithm, random

type
  HittableKind* = enum
    htSphere, htBvhNode, htXyRect, htXzRect, htYzRect, htBox, htDisk, htParaboloid, htHyperboloid
  Hittable* = ref object
    case kind*: HittableKind
    of htSphere: hSphere*: Sphere
    of htBvhNode: hBvhNode*: BvhNode
    of htXyRect: hXyRect*: XyRect
    of htXzRect: hXzRect*: XzRect
    of htYzRect: hYzRect*: YzRect
    of htBox: hBox: Box
    of htDisk: hDisk: Disk
    of htParaboloid: hParaboloid*: Paraboloid
    of htHyperboloid: hHyperboloid*: Hyperboloid

  HittablesList* = object
    len: int # len of data seq
    #size*: int # internal data size
    data*: seq[Hittable] #ptr UncheckedArray[Hittable]

  BvhNode* = object
    left*: Hittable
    right*: Hittable
    box*: AABB

  HitRecord* = object
    p*: Point
    normal*: Vec3
    t*: float
    frontFace*: bool
    mat*: Material

  Sphere* = object
    center*: Point
    radius*: float
    mat*: Material

  XyRect* = object
    mat*: Material
    x0*, x1*, y0*, y1*, k*: float

  XzRect* = object
    mat*: Material
    x0*, x1*, z0*, z1*, k*: float

  YzRect* = object
    mat*: Material
    y0*, y1*, z0*, z1*, k*: float

  Box* = object
    boxMin*: Point
    boxMax*: Point
    sides*: HittablesList

  Disk* = object
    distance*: float # distance along z axis
    radius*: float
    mat*: Material

  Paraboloid* = object
    center*: Point
    radius*: float
    p*: float #distance between focal point and vertex aka center
    zmax*: float #z at radius
    zmin*: float 
    mat*: Material

  Hyperboloid* = object
    center*: Point
    radius*: float
    a*: float #distance between center and vertex
    c*: float #distance between center and focal point
    zmax*: float #z at radius
    zmin*: float 
    mat*: Material

  MaterialKind* = enum
    mkLambertian, mkMetal, mkDielectric
  Material* = object
    case kind*: MaterialKind
    of mkLambertian: mLambertian: Lambertian
    of mkMetal: mMetal: Metal
    of mkDielectric: mDielectric: Dielectric

  Lambertian* = object
    albedo*: Color

  Metal* = object
    albedo*: Color
    fuzz*: float

  Dielectric* = object
    ir*: float # refractive index (could use `eta`)

#proc `=destroy`*(h: var HittablesList) =
#  deallocShared(h.data)
#  h.data = nil
#  h.len = 0

proc initHittables*(size: int = 8): HittablesList =
  ## allocates memory for `size`, but remains empty
  let size = if size < 8: 8 else: size
  result.len = 0
  #result.size = size
  #if size > 0:
  #  result.data = cast[ptr UncheckedArray[Hittable]](allocShared0(sizeof(Hittable) * size))
  result.data = newSeqOfCap[Hittable](size)

proc `[]`*(h: HittablesList, idx: int): Hittable =
  assert idx < h.len
  result = h.data[idx]

proc `[]`*(h: var HittablesList, idx: int): var Hittable =
  assert idx < h.len
  result = h.data[idx]

proc `[]=`*(h: var HittablesList, idx: int, el: Hittable) =
  assert idx < h.len
  h.data[idx] = el

iterator items*(h: HittablesList): Hittable =
  for idx in 0 ..< h.len:
    yield h[idx]

proc initBvhNode*(list: HittablesList, start, stop: int): BvhNode
proc initBvhNode*(list: HittablesList): BvhNode =
  result = initBvhNode(list, 0, list.len)

#proc resize*(h: var HittablesList, newSize: int = 0) =
#  let newLen = if newSize > 0: newSize
#               elif h.size < 8: 8
#               else: h.size * 3 div 2
#  var newBuf = cast[ptr UncheckedArray[Hittable]](allocShared0(sizeof(Hittable) * newLen))
#  if h.size > 0:
#    for idx in 0 ..< newLen:
#      newBuf[idx] = h.data[idx]
#
#    #copyMem(newBuf[0].addr, h.data[0].addr, h.size * sizeof(Hittable))
#    deallocShared(h.data)
#  h.data = newBuf
#  h.size = newLen
#
#proc setLen*(h: var HittablesList, len: int) =
#  if len > h.size:
#    # resize
#    h.resize(len)
#  else:
#    # just set new length
#    h.len = len

proc `[]`*(h: HittablesList, slice: Slice[int]): HittablesList =
  let sliceLen = slice.b - slice.a
  result = initHittables(sliceLen)
  #result.data = cast[ptr UncheckedArray[Hittable]](allocShared0(sizeof(Hittable) * sliceLen))
  for idx in 0 ..< sliceLen:
    result.data[idx] = h.data[slice.a + idx]
  #copyMem(result.data[0].addr, h.data[slice.a].addr, sliceLen * sizeof(Hittable))
  result.len = sliceLen

proc sort*(h: var HittablesList, start, stop: int, cmp: proc(x, y: Hittable): bool,
           order = SortOrder.Ascending) =
  proc locCmp(a, b: Hittable): int =
    let res = cmp(a, b)
    result = if res: 1 else: -1
  h.data.toOpenArray(start, stop-1).sort(locCmp, order = order)

proc add*(h: var HittablesList, el: Hittable) =
  ## adds a new element to h. If space is there
  h.data.add el
  inc h.len
  #if h.len == h.size - 1:
  #  h.resize()
  #inc h.len
  #h[h.len - 1] = el

proc add*(h: var HittablesList, s: Sphere) =
  var ht = Hittable(kind: htSphere)
  ht.hSphere = s
  h.add ht

proc add*(h: var HittablesList, s: Disk) =
  var ht = Hittable(kind: htDisk)
  ht.hDisk = s
  h.add ht

proc add*(h: var HittablesList, b: BvhNode) =
  var ht = Hittable(kind: htBvhNode)
  ht.hBvhNode = b
  h.add ht

proc add*(h: var HittablesList, b: XyRect) =
  var ht = Hittable(kind: htXyRect)
  ht.hXyRect = b
  h.add ht

proc add*(h: var HittablesList, b: XzRect) =
  var ht = Hittable(kind: htXzRect)
  ht.hXzRect = b
  h.add ht

proc add*(h: var HittablesList, b: YzRect) =
  var ht = Hittable(kind: htYzRect)
  ht.hYzRect = b
  h.add ht

proc add*(h: var HittablesList, b: Box) =
  var ht = Hittable(kind: htBox)
  ht.hBox = b
  h.add ht

proc add*(h: var HittablesList, lst: HittablesList) =
  for x in lst:
    h.add x

proc add*(h: var HittablesList, p: Paraboloid) =
  var ht = Hittable(kind: htParaboloid)
  ht.hParaboloid = p
  h.add ht

proc add*(h: var HittablesList, p: Hyperboloid) =
  var ht = Hittable(kind: htHyperboloid)
  ht.hHyperboloid = p
  h.add ht

proc setFaceNormal*(rec: var HitRecord, r: Ray, outward_normal: Vec3) =
  rec.frontFace = r.dir.dot(outward_normal) < 0
  rec.normal = if rec.frontFace: outward_normal else: -outward_normal

proc hit*(h: Hittable, r: Ray, t_min, t_max: float, rec: var HitRecord): bool {.gcsafe.}
proc hit*(n: BvhNode, r: Ray, t_min, t_max: float, rec: var HitRecord): bool =
  if not n.box.hit(r, t_min, t_max):
    return false

  let hitLeft = n.left.hit(r, t_min, t_max, rec)
  let hitRight = n.right.hit(r, t_min, if hitLeft: rec.t else: t_max, rec)

  result = hitLeft or hitRight

proc hit*(h: HittablesList, r: Ray, t_min, t_max: float, rec: var HitRecord): bool =
  var tmpRec: HitRecord
  result = false
  var closestSoFar = t_max

  for obj in h:
    if obj.hit(r, t_min, closestSoFar, tmpRec):
      result = true
      closestSoFar = tmpRec.t
      rec = tmpRec

proc hit*(s: Sphere, r: Ray, t_min, t_max: float, rec: var HitRecord): bool =
  let oc = r.orig - s.center
  let a = r.dir.length_squared()
  let half_b = oc.Vec3.dot(r.dir)
  let c = oc.length_squared() - s.radius * s.radius

  let discriminant = half_b * half_b - a * c
  if discriminant < 0:
    return false
  let sqrtd = sqrt discriminant

  # find nearest root that lies in acceptable range
  var root = (-half_b - sqrtd) / a
  if root < t_min or t_max < root:
    root = (-half_b + sqrtd) / a
    if root < t_min or t_max < root:
      return false

  rec.t = root
  rec.p = r.at(rec.t)
  let outward_normal = (rec.p - s.center) / s.radius
  rec.setFaceNormal(r, outward_normal.Vec3)
  rec.mat = s.mat

  result = true

proc hit*(d: Disk, r: Ray, t_min, t_max: float, rec: var HitRecord): bool =
  let t = (d.distance - r.orig.z) / r.dir.z
  if t < t_min or t > t_max:
    return false
  if r.dir.z == 0.0:
    # ray is parallel to disk
    return false
  let pHit = r.at(t)
  let dist = pHit.x * pHit.x + pHit.y * pHit.y

  if dist > (d.radius * d.radius):
    return false
  rec.t = t
  rec.p = r.at(rec.t)
  let outward_normal = vec3(0, 0, 1)
  rec.setFaceNormal(r, outward_normal.Vec3)
  rec.mat = d.mat

  result = true

proc hit*(rect: XyRect, r: Ray, t_min, t_max: float, rec: var HitRecord): bool =
  let t = (rect.k - r.orig.z) / r.dir.z
  if t < t_min or t > t_max:
    return false
  let x = r.orig.x + t * r.dir.x
  let y = r.orig.y + t * r.dir.y
  if x < rect.x0 or x > rect.x1 or y < rect.y0 or y > rect.y1:
    return false
  #rec.u = (x - rect.x0) / (rect.x1 - rect.x0)
  #rec.v = (y - rect.y0) / (rect.y1 - rect.y0)
  rec.t = t
  let outward_normal = vec3(0, 0, 1)
  rec.setFaceNormal(r, outward_normal)
  rec.mat = rect.mat
  rec.p = r.at(t)
  result = true

proc hit*(rect: XzRect, r: Ray, t_min, t_max: float, rec: var HitRecord): bool =
  let t = (rect.k - r.orig.y) / r.dir.y
  if t < t_min or t > t_max:
    return false
  let x = r.orig.x + t * r.dir.x
  let z = r.orig.z + t * r.dir.z
  if x < rect.x0 or x > rect.x1 or z < rect.z0 or z > rect.z1:
    return false
  #rec.u = (x - rect.x0) / (rect.x1 - rect.x0)
  #rec.v = (y - rect.y0) / (rect.y1 - rect.y0)
  rec.t = t
  let outward_normal = vec3(0, 1, 0)
  rec.setFaceNormal(r, outward_normal)
  rec.mat = rect.mat
  rec.p = r.at(t)
  result = true

proc hit*(rect: YzRect, r: Ray, t_min, t_max: float, rec: var HitRecord): bool =
  let t = (rect.k - r.orig.x) / r.dir.x
  if t < t_min or t > t_max:
    return false
  let y = r.orig.y + t * r.dir.y
  let z = r.orig.z + t * r.dir.z
  if y < rect.y0 or y > rect.y1 or z < rect.z0 or z > rect.z1:
    return false
  #rec.u = (x - rect.x0) / (rect.x1 - rect.x0)
  #rec.v = (y - rect.y0) / (rect.y1 - rect.y0)
  rec.t = t
  let outward_normal = vec3(1, 0, 0)
  rec.setFaceNormal(r, outward_normal)
  rec.mat = rect.mat
  rec.p = r.at(t)
  result = true

proc hit*(box: Box, r: Ray, t_min, t_max: float, rec: var HitRecord): bool =
  result = box.sides.hit(r, t_min, t_max, rec)

proc hit*(p: Paraboloid, r: Ray, t_min, t_max: float, rec: var HitRecord): bool = #not rotatable, has to be parallel to z axis
  let k = p.zmax / (p.radius * p.radius)
  #[let a = k * (r.dir.x * r.dir.x + r.dir.y * r.dir.y)#
  let half_b = k * (r.orig.x * r.dir.x + r.orig.y * r.dir.y) - r.dir.z  #
  let c = k * ]#
  let a = r.dir.x * r.dir.x + r.dir.y * r.dir.y
  let half_b = (- p.center.x + r.orig.x) * r.dir.x + (- p.center.y + r.orig.y) * r.dir.y - 2.0 * r.dir.z * p.p
  let c = p.center.x * (p.center.x - 2.0 * r.orig.x) + r.orig.x * r.orig.x + p.center.y * (p.center.y - 2.0 * r.orig.y) + r.orig.y * r.orig.y + 4.0 * (p.center.z - r.orig.z) * p.p


  let discriminant = half_b * half_b - a * c
  if discriminant < 0:
    return false
  let sqrtd = sqrt discriminant

  # find nearest root that lies in acceptable range
  var root = (-half_b - sqrtd) / a
  if root < t_min or t_max < root:
    root = (-half_b + sqrtd) / a
    if root < t_min or t_max < root:
      return false

  rec.t = root
  rec.p = r.at(rec.t)
  if rec.p.z < p.zmin or rec.p.z > p.zmax:
    return false
  let outward_normal = unitVector(vec3(2.0 * rec.p.x, 2.0 * rec.p.y, - 4.0 * p.p))
  rec.setFaceNormal(r, outward_normal.Vec3)
  rec.mat = p.mat

  result = true

proc hit*(p: Hyperboloid, r: Ray, t_min, t_max: float, rec: var HitRecord): bool = #not rotatable, has to be parallel to z axis
  let oc = r.orig - p.center
  let a = - p.a * p.a * r.dir.length_squared() + p.c * p.c * r.dir.z
  let half_b = 0.5 * (- p.a * p.a * oc.Vec3.dot(r.dir) + p.c * p.c * (r.orig.z - p.center.z) * r.dir.z)
  let c = - p.a * p.a * oc.length_squared()  + p.c * p.c * (r.orig.z - p.center.z) * (r.orig.z - p.center.z) - p.a * p.a * (p.a * p.a + p.c * p.c)

  let discriminant = half_b * half_b - a * c
  if discriminant < 0:
    return false
  let sqrtd = sqrt discriminant

  # find nearest root that lies in acceptable range
  var root = (-half_b - sqrtd) / a
  if root < t_min or t_max < root:
    root = (-half_b + sqrtd) / a
    if root < t_min or t_max < root:
      return false

  rec.t = root
  rec.p = r.at(rec.t)
  if rec.p.z < p.zmin or rec.p.z > p.zmax:
    return false
  let outward_normal = unitVector(vec3( 2.0 * rec.p.x / ( - p.a * p.a + p.c * p.c),  2.0 * rec.p.y / ( - p.a * p.a + p.c * p.c), - 2.0 * rec.p.z / (p.a * p.a)))
  rec.setFaceNormal(r, outward_normal.Vec3)
  rec.mat = p.mat

  result = true

proc hit*(h: Hittable, r: Ray, t_min, t_max: float, rec: var HitRecord): bool {.gcsafe.} =
  case h.kind
  of htSphere: result = h.hSphere.hit(r, t_min, t_max, rec)
  of htDisk: result = h.hDisk.hit(r, t_min, t_max, rec)
  of htBvhNode: result = h.hBvhNode.hit(r, t_min, t_max, rec)
  of htXyRect: result = h.hXyRect.hit(r, t_min, t_max, rec)
  of htXzRect: result = h.hXzRect.hit(r, t_min, t_max, rec)
  of htYzRect: result = h.hYzRect.hit(r, t_min, t_max, rec)
  of htBox: result = h.hBox.hit(r, t_min, t_max, rec)
  of htParaboloid: result = h.hParaboloid.hit(r, t_min, t_max, rec)
  of htHyperboloid: result = h.hHyperboloid.hit(r, t_min, t_max, rec)

proc boundingBox*(s: Sphere, output_box: var AABB): bool =
  ##
  output_box = initAabb(
    s.center - point(s.radius, s.radius, s.radius),
    s.center + point(s.radius, s.radius, s.radius)
  )
  result = true

proc boundingBox*(s: Disk, output_box: var AABB): bool =
  ## in z direction only a small width
  output_box = initAabb(
    - point(s.radius, s.radius, s.distance - 0.0001),
    + point(s.radius, s.radius, s.distance + 0.0001)
  )
  result = true

proc boundingBox*(n: BvhNode, outputBox: var AABB): bool =
  outputBox = n.box
  result = true

proc boundingBox*(r: XyRect, outputBox: var AABB): bool =
  ## bounding box needs to have a non-zero width in each dimension!
  outputBox = initAabb(point(r.x0, r.y0, r.k - 0.0001),
                       point(r.x1, r.y1, r.k + 0.0001))
  result = true

proc boundingBox*(r: XzRect, outputBox: var AABB): bool =
  ## bounding box needs to have a non-zero width in each dimension!
  outputBox = initAabb(point(r.x0, r.k - 0.0001, r.z0),
                       point(r.x1, r.k + 0.0001, r.z1))
  result = true

proc boundingBox*(r: YzRect, outputBox: var AABB): bool =
  ## bounding box needs to have a non-zero width in each dimension!
  outputBox = initAabb(point(r.k - 0.0001, r.y0, r.z0),
                       point(r.k + 0.0001, r.y1, r.z1))
  result = true

proc boundingBox*(b: Box, outputBox: var AABB): bool =
  outputBox = initAabb(b.boxMin, b.boxMax)
  result = true

proc boundingBox*(p: Paraboloid, output_box: var AABB): bool =
  ##
  output_box = initAabb(
    point(p.radius, p.radius, p.zmin),
    point(p.radius, p.radius, p.zmax)
  )
  result = true

proc boundingBox*(p: Hyperboloid, output_box: var AABB): bool =
  ##
  output_box = initAabb(
    point(p.radius, p.radius, p.zmin),
    point(p.radius, p.radius, p.zmax)
  )
  result = true

proc boundingBox*(h: Hittable, output_box: var AABB): bool =
  case h.kind
  of htSphere: result = h.hSphere.boundingBox(output_box)
  of htDisk: result = h.hDisk.boundingBox(output_box)
  of htBvhNode: result = h.hBvhNode.boundingBox(output_box)
  of htXyRect: result = h.hXyRect.boundingBox(output_box)
  of htXzRect: result = h.hXzRect.boundingBox(output_box)
  of htYzRect: result = h.hYzRect.boundingBox(output_box)
  of htBox: result = h.hBox.boundingBox(output_box)
  of htParaboloid: result = h.hParaboloid.boundingBox(output_box)
  of htHyperboloid: result = h.hHyperboloid.boundingBox(output_box)

proc boundingBox*(h: HittablesList, output_box: var AABB): bool =
  if h.len == 0:
    return false

  var tmpBox: AABB
  var firstBox = true

  for obj in h:
    if not obj.boundingBox(tmpBox):
      return false
    output_box = if firstBox: tmpBox else: surroundingBox(output_box, tmpBox)
    firstBox = false
  result = true

proc box_compare(a, b: Hittable, axis: int): bool {.inline.} =
  var boxA: AABB
  var boxB: AABB

  if not a.boundingBox(boxA) or not b.boundingBox(boxB):
    stderr.write("No bounding box in BVH node constructor!\n")

  result = boxA.minimum[axis] < boxB.minimum[axis]

proc box_x_compare(a, b: Hittable): bool =
  result = boxCompare(a, b, 0)

proc box_y_compare(a, b: Hittable): bool =
  result = boxCompare(a, b, 1)

proc box_z_compare(a, b: Hittable): bool =
  result = boxCompare(a, b, 2)

proc initBvhNode*(list: HittablesList, start, stop: int): BvhNode =
  var mlist = list

  let axis = rand(2)
  var comparator: (proc(a, b: Hittable): bool)
  case axis
  of 0: comparator = box_x_compare
  of 1: comparator = box_y_compare
  of 2: comparator = box_z_compare
  else: doAssert false, "Invalid int in range 0,2"

  let objSpan = stop - start
  if objSpan == 1:
    result.left = list[start]
    result.right = list[start]
  elif objSpan == 2:
    if comparator(list[start], list[start+1]):
      result.left = list[start]
      result.right = list[start+1]
    else:
      result.left = list[start+1]
      result.right = list[start]
  else:
    mlist.sort(start, stop, comparator)

    let mid = start + objSpan div 2
    result.left = Hittable(kind: htBvhNode, hBvhNode: initBvhNode(mlist, start, mid))
    result.right = Hittable(kind: htBvhNode, hBvhNode: initBvhNode(mlist, mid, stop))

  var boxLeft: AABB
  var boxRight: AABB

  if not result.left.boundingBox(boxLeft) or
     not result.right.boundingBox(boxRight):
    stderr.write("No bounding box in BVH node constructor!\n")

  result.box = surroundingBox(boxLeft, boxRight)

proc initLambertian*(a: Color): Lambertian =
  result = Lambertian(albedo: a)

proc initMetal*(a: Color, f: float): Metal =
  result = Metal(albedo: a, fuzz: f)

proc initDielectric*(ir: float): Dielectric =
  result = Dielectric(ir: ir)

proc initMaterial*[T](m: T): Material =
  when T is Lambertian:
    result = Material(kind: mkLambertian, mLambertian: m)
  elif T is Metal:
    result = Material(kind: mkMetal, mMetal: m)
  else:
    result = Material(kind: mkDielectric, mDielectric: m)

proc initSphere*(center: Point, radius: float, mat: Material): Sphere =
  result = Sphere(center: center, radius: radius, mat: mat)

proc initDisk*(distance: float, radius: float, mat: Material): Disk =
  result = Disk(distance: distance, radius: radius, mat: mat)

proc initXyRect*(x0, x1, y0, y1, k: float, mat: Material): XyRect =
  result = XyRect(x0: x0, x1: x1, y0: y0, y1: y1, k: k, mat: mat)

proc initXzRect*(x0, x1, z0, z1, k: float, mat: Material): XzRect =
  result = XzRect(x0: x0, x1: x1, z0: z0, z1: z1, k: k, mat: mat)

proc initYzRect*(y0, y1, z0, z1, k: float, mat: Material): YzRect =
  result = YzRect(y0: y0, y1: y1, z0: z0, z1: z1, k: k, mat: mat)

proc initBox*(p0, p1: Point, mat: Material): Box =
  result.boxMin = p0
  result.boxMax = p1

  result.sides = initHittables(0)

  result.sides.add initXyRect(p0.x, p1.x, p0.y, p1.y, p1.z, mat)
  result.sides.add initXyRect(p0.x, p1.x, p0.y, p1.y, p0.z, mat)

  result.sides.add initXzRect(p0.x, p1.x, p0.z, p1.z, p1.y, mat)
  result.sides.add initXzRect(p0.x, p1.x, p0.z, p1.z, p0.y, mat)

  result.sides.add initYzRect(p0.y, p1.y, p0.z, p1.z, p1.x, mat)
  result.sides.add initYzRect(p0.y, p1.y, p0.z, p1.z, p0.x, mat)

proc initParaboloid*(center: Point, radius: float, p: float, zmax: float, zmin: float, mat: Material): Paraboloid =
  result = Paraboloid(center: center, radius: radius, p: p, zmax: zmax, zmin: zmin, mat: mat)

proc initHyperboloid*(center: Point, radius: float, a: float, c: float, zmax: float, zmin: float, mat: Material): Hyperboloid =
  result = Hyperboloid(center: center, radius: radius, a:a, c:c, zmax: zmax, zmin: zmin, mat: mat)

proc scatter*(l: Lambertian, r_in: Ray, rec: HitRecord,
              attenuation: var Color, scattered: var Ray): bool =
  var scatter_direction = rec.normal + randomUnitVector()

  # catch degenerate scatter direction
  if scatter_direction.nearZero():
    scatter_direction = rec.normal

  scattered = initRay(rec.p, scatter_direction)
  attenuation = l.albedo
  result = true

proc scatter*(m: Metal, r_in: Ray, rec: HitRecord,
              attenuation: var Color, scattered: var Ray): bool =
  var reflected = unitVector(r_in.dir).reflect(rec.normal)
  scattered = initRay(rec.p, reflected + m.fuzz * randomInUnitSphere())
  attenuation = m.albedo
  result = scattered.dir.dot(rec.normal) > 0

proc reflectance(cosine, refIdx: float): float =
  ## use Schlick's approximation for reflectance
  var r0 = (1 - refIdx) / (1 + refIdx)
  r0 = r0 * r0
  result = r0 + (1 - r0) * pow(1 - cosine, 5)

proc scatter*(m: Dielectric, r_in: Ray, rec: HitRecord,
              attenuation: var Color, scattered: var Ray): bool =
  attenuation = color(1.0, 1.0, 1.0)
  let refractionRatio = if rec.frontFace: (1.0 / m.ir) else: m.ir

  let unitDirection = unitVector(r_in.dir)
  let cosTheta = min(dot(-unitDirection, rec.normal), 1.0)
  let sinTheta = sqrt(1.0 - cosTheta * cosTheta)

  let cannotRefract = refraction_ratio * sinTheta > 1.0
  var direction: Vec3

  if cannotRefract or reflectance(cosTheta, refractionRatio) > rand(1.0):
    direction = reflect(unitDirection, rec.normal)
  else:
    direction = refract(unitDirection, rec.normal, refractionRatio)

  scattered = initRay(rec.p, direction)
  result = true

proc scatter*(m: Material, r_in: Ray, rec: HitRecord,
              attenuation: var Color, scattered: var Ray): bool =
  case m.kind
  of mkLambertian: result = m.mLambertian.scatter(r_in, rec, attenuation, scattered)
  of mkMetal: result = m.mMetal.scatter(r_in, rec, attenuation, scattered)
  of mkDielectric: result = m.mDielectric.scatter(r_in, rec, attenuation, scattered)
