import mongoose from 'mongoose';
import { env } from './env.js';
import { logger } from './logger.js';

mongoose.set('strictQuery', true);

export async function connectDb() {
  mongoose.connection.on('connected', () => logger.info('mongodb connected'));
  mongoose.connection.on('disconnected', () => logger.warn('mongodb disconnected'));
  mongoose.connection.on('error', (err) => logger.error({ err }, 'mongodb error'));

  await mongoose.connect(env.MONGODB_URI, {
    serverSelectionTimeoutMS: 8000,
    maxPoolSize: 20,
  });

  return mongoose.connection;
}

export async function disconnectDb() {
  await mongoose.connection.close();
}
