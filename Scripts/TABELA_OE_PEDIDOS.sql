/* ===========================================================================
   SAT - Integracao com Marketplaces
   Tabela OE_PEDIDOS (substitui MARKETPLACE_PEDIDOS)
   ---------------------------------------------------------------------------
   Banco.....: Firebird
   Gerado em.: 04/11/2026
   Autor.....: TI Denis Ripol - Desenvolvimento de Sistemas

   PARA QUE SERVE
   --------------
   Controle da baixa de pedidos de marketplace no SAT (botao "Baixar Pedido
   SAT" da tela de Pedidos): cada pedido baixado grava uma linha aqui
   apontando para a OE gerada.

   O QUE MUDOU
   -----------
   1. Nome: MARKETPLACE_PEDIDOS passa a se chamar OE_PEDIDOS (padrao de
      nomenclatura). O Firebird nao renomeia tabela, entao o script cria a
      OE_PEDIDOS e copia os registros da MARKETPLACE_PEDIDOS.
   2. Campo novo DATA: a PK da OE e' ID_OE + DATA, entao so' o CODOE nao
      identifica a OE. CODOE + DATA aponta exatamente para a OE gerada.

   PROTECAO CONTRA DUPLICIDADE
   ---------------------------
   - UK_OE_PEDIDOS_CHAVE (LOJA, COD_MARKETPLACE, COD_PEDIDO_MARKETPLACE):
     o mesmo pedido do marketplace nao e' baixado duas vezes.
   - UK_OE_PEDIDOS_OE (CODOE, DATA): a mesma OE nao fica ligada a dois
     pedidos.

   E SEGURO RODAR MAIS DE UMA VEZ: cada passo confere se ja foi feito.

   {ATENCAO} A MARKETPLACE_PEDIDOS NAO e' apagada por este script. Depois de
   conferir a copia (consulta no final) e atualizar o SATSincroniaMarketplace,
   rode o bloco "REMOCAO DA TABELA ANTIGA" que esta comentado no final.
   ===========================================================================*/

SET TERM ^ ;

/* 1. Tabela */
EXECUTE BLOCK AS
BEGIN
  IF (NOT EXISTS(SELECT 1 FROM RDB$RELATIONS
                  WHERE RDB$RELATION_NAME = 'OE_PEDIDOS')) THEN
    EXECUTE STATEMENT
      'CREATE TABLE OE_PEDIDOS (' ||
      '  ID                      INTEGER NOT NULL,' ||
      '  LOJA                    INTEGER NOT NULL,' ||
      '  COD_MARKETPLACE         INTEGER NOT NULL,' ||
      '  COD_PEDIDO_MARKETPLACE  VARCHAR(100) NOT NULL,' ||
      '  CODOE                   INTEGER NOT NULL,' ||
      '  DATA                    TIMESTAMP NOT NULL,' ||
      '  DATABAIXA               TIMESTAMP,' ||
      '  CONSTRAINT PK_OE_PEDIDOS PRIMARY KEY (ID),' ||
      '  CONSTRAINT UK_OE_PEDIDOS_CHAVE UNIQUE ' ||
      '    (LOJA, COD_MARKETPLACE, COD_PEDIDO_MARKETPLACE),' ||
      '  CONSTRAINT UK_OE_PEDIDOS_OE UNIQUE (CODOE, DATA))';
END^

/* 2. Generator */
EXECUTE BLOCK AS
BEGIN
  IF (NOT EXISTS(SELECT 1 FROM RDB$GENERATORS
                  WHERE RDB$GENERATOR_NAME = 'GEN_OE_PEDIDOS_ID')) THEN
    EXECUTE STATEMENT 'CREATE SEQUENCE GEN_OE_PEDIDOS_ID';
END^

SET TERM ; ^
COMMIT;
SET TERM ^ ;

/* 3. Trigger do ID */
CREATE OR ALTER TRIGGER OE_PEDIDOS_BI FOR OE_PEDIDOS
ACTIVE BEFORE INSERT POSITION 0
AS
BEGIN
  IF (NEW.ID IS NULL) THEN
    NEW.ID = GEN_ID(GEN_OE_PEDIDOS_ID, 1);
END^

/* 4. Copia os registros da MARKETPLACE_PEDIDOS (mantendo o ID).
      DATA = data da OE com esse ID_OE e o mesmo numero de pedido (XPED);
      se a OE nao for encontrada, usa o dia da baixa. */
EXECUTE BLOCK AS
DECLARE VARIABLE MaiorID INTEGER;
BEGIN
  IF (EXISTS(SELECT 1 FROM RDB$RELATIONS
              WHERE RDB$RELATION_NAME = 'MARKETPLACE_PEDIDOS')) THEN
    EXECUTE STATEMENT
      'INSERT INTO OE_PEDIDOS (ID, LOJA, COD_MARKETPLACE, ' ||
      '  COD_PEDIDO_MARKETPLACE, CODOE, DATA, DATABAIXA) ' ||
      'SELECT P.ID, P.LOJA, P.COD_MARKETPLACE, P.COD_PEDIDO_MARKETPLACE, ' ||
      '  P.CODOE, ' ||
      '  COALESCE((SELECT MAX(O.DATA) FROM OE O ' ||
      '             WHERE O.ID_OE = P.CODOE ' ||
      '               AND O.XPED = P.COD_PEDIDO_MARKETPLACE), ' ||
      '           CAST(CAST(P.DATABAIXA AS DATE) AS TIMESTAMP)), ' ||
      '  P.DATABAIXA ' ||
      'FROM MARKETPLACE_PEDIDOS P ' ||
      'WHERE P.CODOE IS NOT NULL ' ||
      '  AND NOT EXISTS (SELECT 1 FROM OE_PEDIDOS N ' ||
      '                   WHERE N.LOJA = P.LOJA ' ||
      '                     AND N.COD_MARKETPLACE = P.COD_MARKETPLACE ' ||
      '                     AND N.COD_PEDIDO_MARKETPLACE = P.COD_PEDIDO_MARKETPLACE)';

  /* Generator continua depois do maior ID copiado */
  SELECT COALESCE(MAX(ID), 0) FROM OE_PEDIDOS INTO :MaiorID;
  IF (MaiorID > GEN_ID(GEN_OE_PEDIDOS_ID, 0)) THEN
    EXECUTE STATEMENT
      'ALTER SEQUENCE GEN_OE_PEDIDOS_ID RESTART WITH ' || MaiorID;
END^

SET TERM ; ^

COMMIT;

/* ===========================================================================
   CONFERENCIA
   1) Registros copiados (com a data da OE):
   ===========================================================================*/
SELECT ID, LOJA, COD_MARKETPLACE, COD_PEDIDO_MARKETPLACE, CODOE, DATA,
       DATABAIXA
  FROM OE_PEDIDOS
 ORDER BY ID;

/* 2) Registros da tabela antiga que NAO foram copiados - o esperado e'
      nenhuma linha. (Da' erro se a MARKETPLACE_PEDIDOS ja foi removida -
      nesse caso e' so' ignorar.) */
SELECT P.*
  FROM MARKETPLACE_PEDIDOS P
 WHERE NOT EXISTS (SELECT 1 FROM OE_PEDIDOS N
                    WHERE N.LOJA = P.LOJA
                      AND N.COD_MARKETPLACE = P.COD_MARKETPLACE
                      AND N.COD_PEDIDO_MARKETPLACE = P.COD_PEDIDO_MARKETPLACE);

/* ===========================================================================
   REMOCAO DA TABELA ANTIGA - so' depois de:
     - a conferencia 2 acima voltar vazia, e
     - o SATSincroniaMarketplace novo (que grava em OE_PEDIDOS) estar
       instalado em todas as estacoes.
   Tire os comentarios e rode:

DROP TRIGGER MARKETPLACE_PEDIDOS_BI;
DROP TABLE MARKETPLACE_PEDIDOS;
DROP SEQUENCE GEN_MARKETPLACE_PEDIDOS_ID;
COMMIT;
   ===========================================================================*/
