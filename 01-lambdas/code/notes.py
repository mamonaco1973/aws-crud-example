import json
import os
import uuid
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

TABLE_NAME = os.environ.get("NOTES_TABLE_NAME", "").strip()
OWNER      = "global"

dynamodb = boto3.resource("dynamodb")


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body)
    }


def _table():
    if not TABLE_NAME:
        raise ValueError("NOTES_TABLE_NAME environment variable is required")
    return dynamodb.Table(TABLE_NAME)


def _note_id(event: dict) -> str:
    try:
        return event.get("pathParameters", {}).get("id", "").strip()
    except AttributeError:
        return ""


def create_handler(event, context):
    try:
        table = _table()
    except ValueError as exc:
        return _response(500, {"error": str(exc)})

    try:
        payload = json.loads(event.get("body", "{}"))
        title   = str(payload.get("title", "")).strip()
        note    = str(payload.get("note", "")).strip()
        if not title:
            raise ValueError("title is required")
        if not note:
            raise ValueError("note is required")
    except (ValueError, json.JSONDecodeError) as exc:
        return _response(400, {"error": f"Invalid request body: {str(exc)}"})

    note_id = str(uuid.uuid4())
    now     = datetime.now(timezone.utc).isoformat()
    item    = {
        "owner":      OWNER,
        "id":         note_id,
        "title":      title,
        "note":       note,
        "created_at": now,
        "updated_at": now
    }

    try:
        table.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(#id)",
            ExpressionAttributeNames={"#id": "id"}
        )
    except ClientError:
        return _response(500, {"error": "Failed to create note"})

    return _response(201, {"id": note_id, "title": title, "note": note})


def list_handler(event, context):
    try:
        table = _table()
    except ValueError as exc:
        return _response(500, {"error": str(exc)})

    try:
        resp  = table.query(KeyConditionExpression=Key("owner").eq(OWNER))
    except ClientError:
        return _response(500, {"error": "Failed to list notes"})

    return _response(200, {"items": resp.get("Items", [])})


def get_handler(event, context):
    try:
        table = _table()
    except ValueError as exc:
        return _response(500, {"error": str(exc)})

    note_id = _note_id(event)
    if not note_id:
        return _response(400, {"error": "Note id is required"})

    try:
        resp = table.get_item(Key={"owner": OWNER, "id": note_id})
    except ClientError:
        return _response(500, {"error": "Failed to retrieve note"})

    item = resp.get("Item")
    if not item:
        return _response(404, {"error": "Note not found"})

    return _response(200, item)


def update_handler(event, context):
    try:
        table = _table()
    except ValueError as exc:
        return _response(500, {"error": str(exc)})

    note_id = _note_id(event)
    if not note_id:
        return _response(400, {"error": "Note id is required"})

    try:
        payload = json.loads(event.get("body", "{}"))
        title   = str(payload.get("title", "")).strip()
        note    = str(payload.get("note", "")).strip()
        if not title:
            raise ValueError("title is required")
        if not note:
            raise ValueError("note is required")
    except (ValueError, json.JSONDecodeError) as exc:
        return _response(400, {"error": f"Invalid request body: {str(exc)}"})

    now = datetime.now(timezone.utc).isoformat()

    try:
        resp = table.update_item(
            Key={"owner": OWNER, "id": note_id},
            UpdateExpression="SET #title = :title, #note = :note, #updated_at = :ts",
            ConditionExpression="attribute_exists(#id)",
            ExpressionAttributeNames={
                "#id": "id", "#title": "title", "#note": "note", "#updated_at": "updated_at"
            },
            ExpressionAttributeValues={":title": title, ":note": note, ":ts": now},
            ReturnValues="ALL_NEW"
        )
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        if code == "ConditionalCheckFailedException":
            return _response(404, {"error": "Note not found"})
        return _response(500, {"error": "Failed to update note"})

    return _response(200, resp.get("Attributes", {}))


def delete_handler(event, context):
    try:
        table = _table()
    except ValueError as exc:
        return _response(500, {"error": str(exc)})

    note_id = _note_id(event)
    if not note_id:
        return _response(400, {"error": "Note id is required"})

    try:
        table.delete_item(
            Key={"owner": OWNER, "id": note_id},
            ConditionExpression="attribute_exists(#id)",
            ExpressionAttributeNames={"#id": "id"}
        )
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        if code == "ConditionalCheckFailedException":
            return _response(404, {"error": "Note not found"})
        return _response(500, {"error": "Failed to delete note"})

    return _response(200, {"message": "Note deleted"})
