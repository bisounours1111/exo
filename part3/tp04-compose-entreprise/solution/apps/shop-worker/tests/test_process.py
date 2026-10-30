from worker.main import process

def test_rejects_large_orders():
    assert process({"id": 1, "productId": 1, "quantity": 500}, None) == "rejected"

def test_confirms_normal_orders():
    assert process({"id": 2, "productId": 1, "quantity": 2}, None) == "confirmed"
