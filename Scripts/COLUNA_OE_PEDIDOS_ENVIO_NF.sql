/* ===========================================================================
   SAT - Integracao com Marketplaces
   Nova coluna OE_PEDIDOS.DATA_ENVIO_NF
   ---------------------------------------------------------------------------
   Banco.....: Firebird
   Gerado em.: 04/11/2026
   Autor.....: TI Denis Ripol - Desenvolvimento de Sistemas

   PARA QUE SERVE
   --------------
   Data/hora em que a nota fiscal do pedido foi enviada ao marketplace pelo
   botao "Enviar Nota Fiscal" da tela de Pedidos. A tela usa esse campo para
   deixar de mostrar os pedidos ja finalizados com a nota enviada.

   PRE-REQUISITO: TABELA_OE_PEDIDOS.sql ja executado.

   COMO RODAR
   ----------
   - No DBeaver: selecione o bloco EXECUTE BLOCK inteiro (ate o END) e
     aperte Ctrl+Enter. Depois rode a consulta de conferencia.
   - No isql: rode o arquivo normalmente (-i); o SET TERM abaixo e' so' para
     o isql - no DBeaver NAO selecione as linhas de SET TERM.

   E SEGURO RODAR MAIS DE UMA VEZ: so cria a coluna se ela nao existir.
   ===========================================================================*/

SET TERM ^ ;

EXECUTE BLOCK AS
BEGIN
  IF (NOT EXISTS(SELECT 1 FROM RDB$RELATION_FIELDS
                  WHERE RDB$RELATION_NAME = 'OE_PEDIDOS'
                    AND RDB$FIELD_NAME = 'DATA_ENVIO_NF')) THEN
    EXECUTE STATEMENT
      'ALTER TABLE OE_PEDIDOS ADD DATA_ENVIO_NF TIMESTAMP';
END
^

SET TERM ; ^

COMMIT;

/* ===========================================================================
   CONFERENCIA - o esperado e' uma linha: DATA_ENVIO_NF
   ===========================================================================*/
SELECT TRIM(RDB$FIELD_NAME) AS CAMPO
  FROM RDB$RELATION_FIELDS
 WHERE RDB$RELATION_NAME = 'OE_PEDIDOS'
   AND RDB$FIELD_NAME = 'DATA_ENVIO_NF';
