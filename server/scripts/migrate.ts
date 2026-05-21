import { Client } from 'pg';
import * as fs from 'fs';
import * as path from 'path';
import dotenv from 'dotenv';

dotenv.config();

// Découpe le SQL en instructions individuelles en gérant les blocs $$ ... $$
function splitStatements(sql: string): string[] {
  const statements: string[] = [];
  let current = '';
  let inDollarQuote = false;
  let dollarTag = '';
  let i = 0;

  while (i < sql.length) {
    if (!inDollarQuote && sql[i] === '$') {
      const end = sql.indexOf('$', i + 1);
      if (end !== -1) {
        const tag = sql.substring(i, end + 1);
        inDollarQuote = true;
        dollarTag = tag;
        current += tag;
        i = end + 1;
        continue;
      }
    } else if (inDollarQuote && sql.startsWith(dollarTag, i)) {
      inDollarQuote = false;
      current += dollarTag;
      i += dollarTag.length;
      continue;
    }

    if (!inDollarQuote && sql[i] === ';') {
      const stmt = current.trim();
      if (stmt) statements.push(stmt);
      current = '';
      i++;
      continue;
    }

    current += sql[i];
    i++;
  }

  const last = current.trim();
  if (last) statements.push(last);

  return statements;
}

async function migrate() {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    console.error('Erreur : DATABASE_URL est manquant dans le fichier .env');
    process.exit(1);
  }

  const url = new URL(connectionString);
  const dbName = url.pathname.replace('/', '');
  url.pathname = '/postgres';
  const adminConnectionString = url.toString();

  // Étape 1 : supprimer et recréer la base
  const adminClient = new Client({ connectionString: adminConnectionString });
  try {
    await adminClient.connect();
    await adminClient.query(`
      SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE datname = $1 AND pid <> pg_backend_pid()
    `, [dbName]);
    await adminClient.query(`DROP DATABASE IF EXISTS "${dbName}"`);
    await adminClient.query(`CREATE DATABASE "${dbName}"`);
    console.log(`Base de données "${dbName}" recréée.`);
  } catch (err) {
    console.error('Erreur lors de la (re)création de la base :', err);
    process.exit(1);
  } finally {
    await adminClient.end();
  }

  // Étape 2 : lire et découper le schéma SQL en instructions individuelles
  const schemaPath = path.resolve(__dirname, '../../gestimed_schema.sql');
  const rawSql = fs.readFileSync(schemaPath, 'utf-8');
  const statements = splitStatements(rawSql).filter(
    (s) => !/^\s*CREATE\s+DATABASE\b/i.test(s)
  );

  // Étape 3 : exécuter chaque instruction séparément
  const client = new Client({ connectionString });
  try {
    await client.connect();
    for (const stmt of statements) {
      await client.query(stmt);
    }
    console.log(`Migration terminée : ${statements.length} instructions exécutées avec succès.`);
  } catch (err) {
    console.error('Erreur lors de la migration :', err);
    process.exit(1);
  } finally {
    await client.end();
  }
}

migrate();
