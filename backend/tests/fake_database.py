import asyncio
from copy import deepcopy

import mongomock


class Cursor:
    def __init__(self, cursor):
        self.cursor = cursor

    def sort(self, *args):
        self.cursor = self.cursor.sort(*args)
        return self

    def skip(self, count):
        self.cursor = self.cursor.skip(count)
        return self

    def limit(self, count):
        self.cursor = self.cursor.limit(count)
        return self

    async def to_list(self, length=None):
        rows = list(self.cursor)
        return rows if length is None else rows[:length]

    def __aiter__(self):
        self.iterator = iter(self.cursor)
        return self

    async def __anext__(self):
        try:
            return next(self.iterator)
        except StopIteration:
            raise StopAsyncIteration


class Collection:
    def __init__(self, collection):
        self.raw = collection
        self.fail_next = {}

    def _call(self, method, *args, **kwargs):
        kwargs.pop("session", None)
        if method in self.fail_next:
            raise self.fail_next.pop(method)
        return getattr(self.raw, method)(*args, **kwargs)

    def find(self, *args, **kwargs):
        return Cursor(self._call("find", *args, **kwargs))

    def aggregate(self, *args, **kwargs):
        return Cursor(self._call("aggregate", *args, **kwargs))

    async def find_one(self, *args, **kwargs):
        return self._call("find_one", *args, **kwargs)

    async def insert_one(self, *args, **kwargs):
        return self._call("insert_one", *args, **kwargs)

    async def update_one(self, *args, **kwargs):
        return self._call("update_one", *args, **kwargs)

    async def update_many(self, *args, **kwargs):
        return self._call("update_many", *args, **kwargs)

    async def find_one_and_update(self, *args, **kwargs):
        query, update = args
        previous = self._call("find_one", query, sort=kwargs.get("sort"))
        if previous is None and not kwargs.get("upsert"):
            return None
        result = self._call("update_one", query, update, upsert=kwargs.get("upsert", False))
        if kwargs.get("return_document"):
            return self._call("find_one", {"_id": previous["_id"] if previous else result.upserted_id}, kwargs.get("projection"))
        return previous

    async def count_documents(self, *args, **kwargs):
        return self._call("count_documents", *args, **kwargs)

    async def delete_one(self, *args, **kwargs):
        return self._call("delete_one", *args, **kwargs)

    async def distinct(self, *args, **kwargs):
        return self._call("distinct", *args, **kwargs)


class Session:
    def __init__(self, client):
        self.client = client

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_):
        return False

    async def with_transaction(self, operation):
        async with self.client.lock:
            snapshot = {name: deepcopy(list(self.client.raw[name].find())) for name in self.client.raw.list_collection_names()}
            try:
                return await operation(self)
            except BaseException:
                for name in self.client.raw.list_collection_names():
                    self.client.raw[name].delete_many({})
                    if snapshot.get(name):
                        self.client.raw[name].insert_many(deepcopy(snapshot[name]))
                raise


class Database:
    def __init__(self):
        self.raw = mongomock.MongoClient().tests
        self.raw.wallets.create_index("owner_id", unique=True)
        self.lock = asyncio.Lock()
        self.collections = {}

    def __getattr__(self, name):
        if name not in self.collections:
            self.collections[name] = Collection(self.raw[name])
        return self.collections[name]

    async def start_session(self):
        return Session(self)
