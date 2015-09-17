{-# LANGUAGE FlexibleContexts #-}

-- | A multi-trie is a trie (i.e. a prefix tree) with each node containing a list of values considered as a multiset.
module Data.MultiTrie where

import Prelude hiding (lookup, map, null, repeat)
import qualified Data.Foldable as F
import qualified Data.Map as M
import qualified Data.Tree as T
import qualified Data.List as L
import Control.Applicative hiding (empty)

-- | A map of labels onto child nodes
type MultiTrieMap n v = M.Map n (MultiTrie n v) 

-- | A node object
data MultiTrie n v = MultiTrie
    {
        values :: [v],                  -- ^ multiset
        children :: MultiTrieMap n v    -- ^ child nodes
    }
    deriving (Eq, Show)

-- | Constant: an empty multi-trie. A neutral element with respect to 'union'.
empty :: MultiTrie n v
empty = MultiTrie [] M.empty

-- | A multi-trie containing just one value in its root node's multiset and no child nodes
singleton :: v -> MultiTrie n v
singleton x = MultiTrie [x] M.empty

-- | An infinite multi-trie that has, in each node, the same multiset of values and the same children names
repeat :: Ord n => [n] -> [v] -> MultiTrie n v
repeat ns xs = MultiTrie xs (M.fromList $ zip ns $ L.repeat $ repeat ns xs)

-- | A multi-trie that has all possible values and all possible chid names in each node.
-- A neutral element with respect to 'intersection'. An opposite to the 'empty' multi-trie.
top :: (Ord n, Bounded n, Enum n, Bounded v, Enum v) => MultiTrie n v
top = repeat allValues $ L.cycle allValues

-- | Check whether a multi-trie is empty
null :: MultiTrie n v -> Bool
null (MultiTrie vs m) = L.null vs && L.all null (M.elems m)

-- | A total number of values in all nodes
size :: MultiTrie n v -> Int
size (MultiTrie vs m) = L.length vs + L.sum (L.map size (M.elems m))

-- | Select a multi-trie subnode identified by the given path ('empty' if there is no such path)
lookup :: Ord n => [n] -> MultiTrie n v -> MultiTrie n v
lookup [] mt = mt
lookup (n:ns) (MultiTrie _ m) = maybe empty (lookup ns) (M.lookup n m)

-- | A multiset of values from a subnode identified by the given path (empty list if there is no such path)
valuesByPath :: Ord n => [n] -> MultiTrie n v -> [v]
valuesByPath ns = values . lookup ns

-- | Perform the given transformation on a subnode identified by the given path
update :: Ord n => [n] -> (MultiTrie n v -> MultiTrie n v) -> MultiTrie n v -> MultiTrie n v
update [] f mt = f mt
update (n:ns) f (MultiTrie vs m) = MultiTrie vs (M.alter (toMaybe . update ns f . fromMaybe) n m)

-- | Add a new value to the root node's multiset of values
add :: v -> MultiTrie n v -> MultiTrie n v
add v (MultiTrie vs m) = MultiTrie (v:vs) m

-- | Add a new value to a multiset of values in a subnode identified by the given path
addByPath :: Ord n => [n] -> v -> MultiTrie n v -> MultiTrie n v
addByPath ns v = update ns (add v)

-- | Replace a subnode identified by the given path with a new given multi-trie
replace :: Ord n => [n] -> MultiTrie n v -> MultiTrie n v -> MultiTrie n v
replace ns mt1 = update ns (const mt1)

-- | Delete a subnode identified by the given path
delete :: Ord n => [n] -> MultiTrie n v -> MultiTrie n v
delete ns = replace ns empty

-- | Replace a subnode identified by the given path with its 'union' against a given multi-trie
unite :: Ord n => [n] -> MultiTrie n v -> MultiTrie n v -> MultiTrie n v
unite ns mt1 = update ns (union mt1)

-- | Replace a subnode identified by the given path with its 'intersection' against a given multi-trie
intersect :: (Ord n, Eq v) => [n] -> MultiTrie n v -> MultiTrie n v -> MultiTrie n v
intersect ns mt1 = update ns (intersection mt1)

-- | Map a function over all values
map :: Ord n => (v -> w) -> MultiTrie n v -> MultiTrie n w
map f = mapContainers (L.map f)

-- | Map a function over all values, together with node paths as well
mapWithPath :: Ord n => ([n] -> v -> w) -> MultiTrie n v -> MultiTrie n w
mapWithPath f = mapContainersWithPath (L.map . f) 

-- | Apply a multiset F of functions to all values.
-- If V is a multi-set of values under a certain path s in a multi-trie P,
-- the result Q will contain under s a multi-set of all (f v) values, for all
-- v from V and all f from F.
mapAll :: Ord n => [v -> w] -> MultiTrie n v -> MultiTrie n w
mapAll fs  = mapContainers (fs <*>)

-- | Apply a multiset of functions to all values, together with node path as well
mapAllWithName :: Ord n => [[n] -> v -> w] -> MultiTrie n v -> MultiTrie n w
mapAllWithName fs = mapContainersWithPath (\ns -> (L.map ($ns) fs <*>))

-- | Map a function over entire multisets
mapContainers :: Ord n => ([v] -> [w]) -> MultiTrie n v -> MultiTrie n w
mapContainers fl (MultiTrie vs vm) = MultiTrie (fl vs) (M.map (mapContainers fl) vm)

-- | Map a function over entire multisets, together witn node path as well
mapContainersWithPath :: Ord n => ([n] -> [v] -> [w]) -> MultiTrie n v -> MultiTrie n w
mapContainersWithPath fl (MultiTrie vs vm) = MultiTrie (fl [] vs) (M.mapWithKey (\n -> mapContainersWithPath $ fl . (n:)) vm)

-- | Cartesian product of two multi-tries P and Q is a multi-trie R whose paths are concatenations of
-- any path s from P and every path t from Q, and values under st in R are pairs (v, w) where v is every
-- value under s in P, and w is every value under t in Q.
cartesianProduct :: Ord n => MultiTrie n v -> MultiTrie n w -> MultiTrie n (v, w)
cartesianProduct mtv = applyCartesian (map (,) mtv)

-- | Union of two multi-tries P and Q is a multi-trie R that contains every path s that is present in
-- either P or Q or both, and a multiset of values under s in R is a union of multisets contained in P
-- and Q under s.
union :: Ord n => MultiTrie n v -> MultiTrie n v -> MultiTrie n v
union = zipContentsAndChildren (++) (M.unionWith union)

-- | Union of a list of multi-tries
unions :: Ord n => [MultiTrie n v] -> MultiTrie n v
unions = L.foldl union empty

-- | Intersection of two multi-tries P and Q is a multi-trie R that contains every path s that is present in
-- either P or Q or both, and a multiset of values under s in R is an intersection of multisets contained in P
-- and Q under s.
intersection :: (Ord n, Eq v) => MultiTrie n v -> MultiTrie n v -> MultiTrie n v
intersection mt = nullToEmpty . zipContentsAndChildren listAsMultiSetIntersection (M.intersectionWith intersection) mt 

-- | Intersection of a list of multi-tries
intersections :: (Ord n, Bounded n, Enum n, Eq v, Bounded v, Enum v) => [MultiTrie n v] -> MultiTrie n v
intersections = L.foldl intersection top 

-- | Given multi-tries P(V1, M1) and Q(V2, M2) and a pair of binary functions:
-- f on multisets of values and g on maps of multi-tries, build a new
-- multi-trie R(f V1 V2, g M1 M2)
zipContentsAndChildren :: Ord n => ([v] -> [v] -> [v]) -> (MultiTrieMap n v -> MultiTrieMap n v -> MultiTrieMap n v) -> MultiTrie n v -> MultiTrie n v -> MultiTrie n v
zipContentsAndChildren f g (MultiTrie vs1 m1) (MultiTrie vs2 m2) = MultiTrie (f vs1 vs2) (g m1 m2) 

-- | Given a multi-trie whose values are multi-tries in their turn, convert it into a 'plain' multi-trie.
-- If P is a multi-trie that contains a multi-trie Q as its value under a path s, and Q contains a value x
-- under a path t, then the plain multi-trie R will contain x as a value under a path st.
flatten :: Ord n => MultiTrie n (MultiTrie n v) -> MultiTrie n v
flatten (MultiTrie mts mtm) = F.foldr union empty mts `union` MultiTrie [] (M.map flatten mtm)

applyCartesian :: Ord n => MultiTrie n (v -> w) -> MultiTrie n v -> MultiTrie n w
applyCartesian mtf mtx = flatten $ map (`map` mtx) mtf

applyUniting :: Ord n => MultiTrie n (v -> w) -> MultiTrie n v -> MultiTrie n w
applyUniting = applyZippingChildren (M.unionWith union)

applyIntersecting :: (Ord n, Eq w) => MultiTrie n (v -> w) -> MultiTrie n v -> MultiTrie n w
applyIntersecting = applyZippingChildren (M.intersectionWith intersection)

applyZippingChildren :: Ord n => (MultiTrieMap n w -> MultiTrieMap n w -> MultiTrieMap n w) -> MultiTrie n (v -> w) -> MultiTrie n v -> MultiTrie n w
applyZippingChildren op mtf@(MultiTrie fs fm) mtx@(MultiTrie xs xm) =
    MultiTrie
        (fs <*> xs)
        (op
            (M.map (applyZippingChildren op mtf) xm)
            (M.map ((flip $ applyZippingChildren op) mtx) fm))

bindCartesian :: Ord n => MultiTrie n v -> (v -> MultiTrie n w) -> MultiTrie n w
bindCartesian mt fmt = flatten $ map fmt mt

toMap :: Ord n => MultiTrie n v -> M.Map [n] [v]
toMap (MultiTrie vs m) = if L.null vs then childrenMap else M.insert [] vs childrenMap
    where
        childrenMap =
            M.unions $
            M.elems $
            M.mapWithKey (\n -> M.mapKeys (n:)) $
            M.map toMap m

fromList :: Ord n => [([n], v)] -> MultiTrie n v
fromList = L.foldr (uncurry addByPath) empty

fromMaybe :: Maybe (MultiTrie n v) -> MultiTrie n v
fromMaybe Nothing = empty
fromMaybe (Just mt) = mt

toMaybe :: MultiTrie n v -> Maybe (MultiTrie n v)
toMaybe mt = if null mt then Nothing else Just mt

nullToEmpty :: MultiTrie n v -> MultiTrie n v
nullToEmpty mt = if null mt then empty else mt

cleanupEmpties :: Ord n => MultiTrie n v -> MultiTrie n v
cleanupEmpties (MultiTrie vs m) = nullToEmpty $ MultiTrie vs (M.map cleanupEmpties m)

toTree :: (n -> t) -> ([v] -> t) -> MultiTrie n v -> T.Tree t
toTree f g (MultiTrie vs m) = T.Node (g vs) $ M.elems $ M.mapWithKey namedChildToTree m
    where
        namedChildToTree k mt = T.Node (f k) [toTree f g mt]

draw :: (Show n, Show [v]) => MultiTrie n v -> String
draw = T.drawTree . toTree show show

listAsMultiSetIntersection :: Eq a => [a] -> [a] -> [a]
listAsMultiSetIntersection [] _ = []
listAsMultiSetIntersection (x:xs) ys = if x `L.elem` ys
    then x : listAsMultiSetIntersection xs (L.delete x ys)
    else listAsMultiSetIntersection xs ys

allValues :: (Bounded a, Enum a) => [a]
allValues = [minBound..]
