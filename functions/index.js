const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

exports.paymongoWebhook = onRequest(async (req, res) => {
  try {
    const body = req.body;

    logger.info("Webhook received:", body);

    const data = body?.data?.attributes || {};

    const status = data?.status;
    const description = data?.description || "";

    // Extract device code (8 chars)
    let deviceCode = null;
    const match = description.match(/([A-Z0-9]{8})/);
    if (match) deviceCode = match[1];

    if (!deviceCode) {
      return res.status(400).send("No device code found");
    }

    if (status !== "paid") {
      return res.status(200).send("Not paid");
    }

    const ref = db.collection("users").doc(deviceCode);

    const now = new Date();
    const newExpiry = new Date();
    newExpiry.setDate(now.getDate() + 30);

    await ref.set(
      {
        isPremium: true,
        expiryDate: admin.firestore.Timestamp.fromDate(newExpiry),
      },
      { merge: true }
    );

    return res.status(200).send("OK");

  } catch (e) {
    logger.error(e);
    return res.status(500).send("Error");
  }
});